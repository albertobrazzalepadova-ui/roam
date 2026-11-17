"""People, follows and direct messages (Instagram-style), plus the pinned ROAM chat.

A person is identified by a key:
  u:<id>    a Roam account
  n:<name>  a traveller who only exists as the author of demo/imported posts (cannot reply)
  roam      the ROAM assistant, always the first, pinned conversation
"""
import json
from datetime import datetime, timezone
from typing import Annotated, Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

import auth
import personalization
from database import db

router = APIRouter()
User = Annotated[dict, Depends(auth.current_user)]
ROAM = 'roam'
VISIBLE_POST = 'FROM social_posts JOIN place_catalog ON place_catalog.id=social_posts.place_id'


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def me_key(user_id: int) -> str:
    return f'u:{user_id}'


def post_author_key(user_id, author: str) -> str:
    return f'u:{user_id}' if user_id is not None else f'n:{author}'


def _posts_where(key: str) -> tuple[str, dict]:
    if key.startswith('u:'):
        return 'social_posts.user_id=:pid', {'pid': int(key[2:])}
    return 'social_posts.user_id IS NULL AND social_posts.author=:pname', {'pname': key[2:]}


def check_key(c, key: str) -> str:
    """404 unless the key names a real account or an author with visible posts."""
    if key.startswith('u:') and key[2:].isdigit():
        if c.execute('SELECT 1 FROM profile WHERE id=?', (int(key[2:]),)).fetchone():
            return key
    elif key.startswith('n:') and 0 < len(key) <= 200:
        where, params = _posts_where(key)
        if c.execute(f'SELECT 1 {VISIBLE_POST} WHERE {where} LIMIT 1', params).fetchone():
            return key
    raise HTTPException(404, 'Viaggiatore non trovato')


def person_lite(c, key: str, me: int) -> dict:
    if key == ROAM:
        return dict(key=ROAM, name='ROAM', photo=None, has_account=False, is_roam=True, mine=False)
    if key.startswith('u:'):
        row = c.execute('SELECT name,photo FROM profile WHERE id=?', (int(key[2:]),)).fetchone()
        name, photo = (row['name'], row['photo']) if row else ('Account eliminato', None)
        return dict(key=key, name=name, photo=photo, has_account=True, is_roam=False, mine=key == me_key(me))
    author = c.execute('SELECT photo FROM author_profiles WHERE name=?', (key[2:],)).fetchone()
    return dict(key=key, name=key[2:], photo=author['photo'] if author else None, has_account=False, is_roam=False, mine=False)


def followed_targets(c, me: int) -> list[str]:
    return [r[0] for r in c.execute('SELECT target FROM follows WHERE follower_id=?', (me,))]


def person(c, key: str, me: int) -> dict:
    result = person_lite(c, key, me)
    where, params = _posts_where(key)
    stats = c.execute(f'SELECT COUNT(*) AS posts, COUNT(DISTINCT social_posts.place_id) AS places {VISIBLE_POST} WHERE {where}', params).fetchone()
    if key.startswith('u:'):
        result['bio'] = c.execute('SELECT bio FROM profile WHERE id=?', (int(key[2:]),)).fetchone()['bio']
        result['following'] = c.execute('SELECT COUNT(*) FROM follows WHERE follower_id=?', (int(key[2:]),)).fetchone()[0]
        result['follows_you'] = bool(c.execute('SELECT 1 FROM follows WHERE follower_id=? AND target=?', (int(key[2:]), me_key(me))).fetchone())
    else:
        author = c.execute('SELECT bio,is_demo FROM author_profiles WHERE name=?', (key[2:],)).fetchone()
        result['bio'] = author['bio'] if author else ''
        result['following'] = 0
        result['follows_you'] = False
        result['is_demo'] = bool(author and author['is_demo'])
    result['posts'], result['places'] = stats['posts'], stats['places']
    result['followers'] = c.execute('SELECT COUNT(*) FROM follows WHERE target=?', (key,)).fetchone()[0]
    result['is_following'] = bool(c.execute('SELECT 1 FROM follows WHERE follower_id=? AND target=?', (me, key)).fetchone())
    return result


def search(c, query: str, me: int) -> list[dict]:
    """Accounts and post authors matched by name; the most active first."""
    like = '%' + query.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%'
    rows = c.execute(
        f"SELECT social_posts.user_id AS uid, author, COUNT(*) AS posts, MAX(created_at) AS last {VISIBLE_POST} "
        "GROUP BY CASE WHEN social_posts.user_id IS NULL THEN 'n:' || author ELSE 'u:' || social_posts.user_id END").fetchall()
    keys = {post_author_key(r['uid'], r['author']): (r['posts'], r['last'] or '') for r in rows}
    for r in c.execute('SELECT id FROM profile WHERE email IS NOT NULL OR id=1'):
        keys.setdefault(me_key(r['id']), (0, ''))
    people = []
    for key, (posts, last) in keys.items():
        p = person_lite(c, key, me)
        if query and not _matches(p['name'], query):
            continue
        people.append((posts, last, p['name'], key))
    people.sort(key=lambda x: (-x[0], -(datetime.fromisoformat(x[1]).timestamp() if x[1] else 0), x[2]))
    return [person(c, key, me) for *_, key in people[:50]]


def _matches(name: str, query: str) -> bool:
    return query.lower() in name.lower()


# --- Follows ----------------------------------------------------------------

class FollowInput(BaseModel):
    key: str = Field(min_length=3, max_length=200)
    follow: bool


@router.get('/people/profile')
def person_profile(key: str, user: User):
    with db() as c:
        return person(c, check_key(c, key), user['id'])


@router.put('/people/follow')
def follow(value: FollowInput, user: User):
    with db() as c:
        key = check_key(c, value.key)
        if key == me_key(user['id']):
            raise HTTPException(422, 'Non puoi seguire te stesso')
        if value.follow:
            changed = c.execute('INSERT OR IGNORE INTO follows(follower_id,target,created_at) VALUES(?,?,?)', (user['id'], key, now())).rowcount
        else:
            changed = c.execute('DELETE FROM follows WHERE follower_id=? AND target=?', (user['id'], key)).rowcount
        result = person(c, key, user['id'])
    if changed and value.follow:
        personalization.track('follow', user['id'], author=result['name'][:80])
    return result


@router.get('/people/connections')
def connections(key: str, kind: Literal['followers', 'following'], user: User):
    with db() as c:
        key = check_key(c, key)
        if kind == 'followers':
            keys = [me_key(r[0]) for r in c.execute('SELECT follower_id FROM follows WHERE target=? ORDER BY created_at DESC', (key,))]
        elif key.startswith('u:'):
            keys = [r[0] for r in c.execute('SELECT target FROM follows WHERE follower_id=? ORDER BY created_at DESC', (int(key[2:]),))]
        else:
            keys = []
        return [person(c, k, user['id']) for k in keys]


# --- Direct messages ----------------------------------------------------------

class OpenConversationInput(BaseModel):
    key: str = Field(min_length=3, max_length=200)


class MessageInput(BaseModel):
    body: str = Field(default='', max_length=2000)
    post_id: str | None = Field(default=None, max_length=200)


class LikedInput(BaseModel):
    liked: bool


def _pair(x: str, y: str) -> tuple[str, str]:
    return (x, y) if x < y else (y, x)


def conversation_with(c, me: int, peer: str) -> str:
    a, b = _pair(me_key(me), peer)
    row = c.execute('SELECT id FROM conversations WHERE a=? AND b=?', (a, b)).fetchone()
    if row:
        return row['id']
    cid = f'roam-{me}' if peer == ROAM else str(uuid4())
    stamp = now()
    c.execute('INSERT INTO conversations(id,a,b,created_at,updated_at) VALUES(?,?,?,?,?)', (cid, a, b, stamp, stamp))
    return cid


def _my_conversation(c, cid: str, me: int):
    row = c.execute('SELECT * FROM conversations WHERE id=?', (cid,)).fetchone()
    mine = me_key(me)
    if not row or mine not in (row['a'], row['b']):
        raise HTTPException(404, 'Conversazione non trovata')
    return row, row['b'] if row['a'] == mine else row['a']


def _read_at(c, cid: str, who: str) -> str:
    row = c.execute('SELECT read_at FROM conversation_reads WHERE conversation_id=? AND person=?', (cid, who)).fetchone()
    return row['read_at'] if row else ''


def _unread(c, cid: str, me: int) -> int:
    return c.execute('SELECT COUNT(*) FROM direct_messages WHERE conversation_id=? AND sender!=? AND created_at>?',
                     (cid, me_key(me), _read_at(c, cid, me_key(me)))).fetchone()[0]


def _message(c, row, me: int) -> dict:
    from main import post_page  # lazy: main imports this module
    result = dict(id=row['id'], body=row['body'], mine=row['sender'] == me_key(me), created_at=row['created_at'],
                  liked=bool(row['liked']), post=None, places=[], posts=[])
    if row['post_id']:
        page = post_page(c, 'social_posts.id=:id', {'id': row['post_id']}, me, 0, 1)['posts']
        result['post'] = page[0] if page else None
        result['post_missing'] = not page
    if row['payload']:
        payload = json.loads(row['payload'])
        result['places'], result['posts'] = payload.get('places', []), payload.get('posts', [])
    return result


def _preview(c, row, me: int) -> dict | None:
    last = c.execute('SELECT * FROM direct_messages WHERE conversation_id=? ORDER BY created_at DESC, id DESC LIMIT 1', (row['id'],)).fetchone()
    if not last:
        return None
    return dict(body=last['body'], mine=last['sender'] == me_key(me), created_at=last['created_at'],
                kind='post' if last['post_id'] else 'text')


@router.get('/dm/conversations')
def conversations(user: User):
    me = user['id']
    with db() as c:
        conversation_with(c, me, ROAM)  # ROAM is always there, even before the first question
        rows = c.execute('SELECT * FROM conversations WHERE a=? OR b=? ORDER BY updated_at DESC', (me_key(me), me_key(me))).fetchall()
        result = []
        for row in rows:
            peer = row['b'] if row['a'] == me_key(me) else row['a']
            last = _preview(c, row, me)
            if last is None and peer != ROAM:
                continue  # opened but never written: not in the inbox, like Instagram
            result.append(dict(id=row['id'], peer=person_lite(c, peer, me), pinned=peer == ROAM, last=last,
                               unread=0 if peer == ROAM else _unread(c, row['id'], me), updated_at=row['updated_at']))
    return sorted(result, key=lambda x: not x['pinned'])  # stable: pinned first, then most recent


@router.get('/dm/unread')
def unread(user: User):
    with db() as c:
        from groups import unread_groups  # lazy: groups imports this module
        rows = c.execute("SELECT id FROM conversations WHERE (a=? OR b=?) AND a!='roam' AND b!='roam'", (me_key(user['id']),) * 2).fetchall()
        return {'count': sum(1 for r in rows if _unread(c, r['id'], user['id'])) + unread_groups(c, user['id'])}


@router.post('/dm/conversations')
def open_conversation(value: OpenConversationInput, user: User):
    with db() as c:
        key = ROAM if value.key == ROAM else check_key(c, value.key)
        if key == me_key(user['id']):
            raise HTTPException(422, 'Non puoi scrivere a te stesso')
        cid = conversation_with(c, user['id'], key)
        return dict(id=cid, peer=person_lite(c, key, user['id']), pinned=key == ROAM, last=None, unread=0, updated_at=now())


@router.get('/dm/conversations/{cid}/messages')
def messages(cid: str, user: User):
    me = user['id']
    with db() as c:
        row, peer = _my_conversation(c, cid, me)
        rows = c.execute('SELECT * FROM (SELECT * FROM direct_messages WHERE conversation_id=? ORDER BY created_at DESC, id DESC LIMIT 200) '
                         'ORDER BY created_at, id', (cid,)).fetchall()
        c.execute('INSERT OR REPLACE INTO conversation_reads(conversation_id,person,read_at) VALUES(?,?,?)', (cid, me_key(me), now()))
        return dict(peer=person(c, peer, me) if peer != ROAM else person_lite(c, ROAM, me),
                    peer_read_at=_read_at(c, cid, peer) or None, messages=[_message(c, r, me) for r in rows])


def add_message(c, cid: str, sender: str, body: str, post_id=None, payload=None) -> dict:
    stamp = now()
    row = dict(id=str(uuid4()), conversation_id=cid, sender=sender, body=body, post_id=post_id,
               payload=json.dumps(payload, ensure_ascii=False) if payload else None, created_at=stamp)
    c.execute('INSERT INTO direct_messages(id,conversation_id,sender,body,post_id,payload,liked,created_at) '
              'VALUES(:id,:conversation_id,:sender,:body,:post_id,:payload,0,:created_at)', row)
    c.execute('UPDATE conversations SET updated_at=? WHERE id=?', (stamp, cid))
    return c.execute('SELECT * FROM direct_messages WHERE id=?', (row['id'],)).fetchone()


@router.post('/dm/conversations/{cid}/messages', status_code=201)
def send(cid: str, value: MessageInput, user: User):
    me = user['id']
    body = value.body.strip()
    if not body and not value.post_id:
        raise HTTPException(422, 'Scrivi un messaggio')
    with db() as c:
        _, peer = _my_conversation(c, cid, me)
        if peer == ROAM:
            raise HTTPException(422, 'Scrivi a ROAM dalla sua chat')
        if value.post_id and not c.execute(f'SELECT 1 {VISIBLE_POST} WHERE social_posts.id=?', (value.post_id,)).fetchone():
            raise HTTPException(404, 'Post non trovato')
        row = add_message(c, cid, me_key(me), body, post_id=value.post_id)
        c.execute('INSERT OR REPLACE INTO conversation_reads(conversation_id,person,read_at) VALUES(?,?,?)', (cid, me_key(me), row['created_at']))
        return _message(c, row, me)


@router.put('/dm/messages/{mid}/liked')
def like_message(mid: str, value: LikedInput, user: User):
    with db() as c:
        row = c.execute('SELECT * FROM direct_messages WHERE id=?', (mid,)).fetchone()
        if not row:
            raise HTTPException(404, 'Messaggio non trovato')
        _my_conversation(c, row['conversation_id'], user['id'])
        if row['sender'] == me_key(user['id']):
            raise HTTPException(422, 'Puoi mettere il cuore solo ai messaggi ricevuti')
        c.execute('UPDATE direct_messages SET liked=? WHERE id=?', (int(value.liked), mid))
        return {'liked': value.liked}


# --- ROAM -------------------------------------------------------------------

def save_roam_exchange(user_id: int, question: str, reply: dict) -> None:
    """Keeps the assistant chat like any other conversation, with its place cards."""
    with db() as c:
        cid = conversation_with(c, user_id, ROAM)
        add_message(c, cid, me_key(user_id), question)
        add_message(c, cid, ROAM, reply['reply'], payload={'places': reply.get('places', []), 'posts': reply.get('posts', [])})


@router.delete('/dm/roam', status_code=204)
def clear_roam(user: User):
    with db() as c:
        c.execute('DELETE FROM direct_messages WHERE conversation_id=?', (conversation_with(c, user['id'], ROAM),))
