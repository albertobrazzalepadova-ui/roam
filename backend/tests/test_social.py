import base64

from test_api import client  # first account
from test_api import local_catalog  # noqa: F401  (autouse fixture)
from test_auth import new_client
import main

PHOTO = base64.b64encode(b'\xff\xd8\xffsocial-follow').decode()


def test_follow_feed_and_counts():
    other, session = new_client('follow-bea@example.com', name='Bea Follow')
    bea = f"u:{session['user']['id']}"
    me = client.get('/auth/me').json()
    with main.db() as c:
        c.execute("INSERT OR REPLACE INTO social_posts(id,place_id,author,body,rating,photo,created_at,saved,mine) VALUES('f-demo','rialto','Nina Demo','Ciao',5,NULL,'2026-11-05T10:00:00+00:00',0,0)")
    post = other.post('/feed/posts', json={'place_id': 'rialto', 'body': 'Dal ponte', 'rating': 5, 'photo': PHOTO}).json()
    assert post['author_key'] == bea and post['following'] is False

    assert client.put('/people/follow', json={'key': f"u:{me['id']}", 'follow': True}).status_code == 422
    assert client.put('/people/follow', json={'key': 'n:Nobody here', 'follow': True}).status_code == 404
    followed = client.put('/people/follow', json={'key': bea, 'follow': True}).json()
    assert followed['is_following'] and followed['followers'] == 1
    assert client.put('/people/follow', json={'key': 'n:Nina Demo', 'follow': True}).json()['is_following']

    feed = client.post('/feed/query', json={'following_only': True}).json()['posts']
    ids = [p['id'] for p in feed]
    assert post['id'] in ids and 'f-demo' in ids and all(p['following'] or p['mine'] for p in feed)

    stats = client.get('/stats').json()
    assert stats['following'] >= 2
    profile = other.get('/people/profile', params={'key': f"u:{me['id']}"}).json()
    assert profile['following'] >= 2
    assert other.get('/people/profile', params={'key': bea}).json()['followers'] == 1
    followers = other.get('/people/connections', params={'key': bea, 'kind': 'followers'}).json()
    assert [p['key'] for p in followers] == [f"u:{me['id']}"]
    assert [p['id'] for p in client.get('/people/posts', params={'key': bea}).json()['posts']] == [post['id']]

    client.put('/people/follow', json={'key': bea, 'follow': False})
    assert post['id'] not in [p['id'] for p in client.post('/feed/query', json={'following_only': True}).json()['posts']]


def test_direct_messages_like_instagram():
    other, session = new_client('dm-carlo@example.com', name='Carlo DM')
    carlo = f"u:{session['user']['id']}"
    me = client.get('/auth/me').json()

    inbox = client.get('/dm/conversations').json()
    assert inbox[0]['pinned'] and inbox[0]['peer']['key'] == 'roam'

    conv = client.post('/dm/conversations', json={'key': carlo}).json()
    assert client.post('/dm/conversations', json={'key': carlo}).json()['id'] == conv['id']
    assert conv['id'] not in [c['id'] for c in client.get('/dm/conversations').json()]  # empty chats stay hidden

    assert client.post(f"/dm/conversations/{conv['id']}/messages", json={'body': '  '}).status_code == 422
    sent = client.post(f"/dm/conversations/{conv['id']}/messages", json={'body': 'Ciao Carlo!'}).json()
    assert sent['mine'] and sent['body'] == 'Ciao Carlo!'

    # Carlo sees it unread, with the same conversation id.
    assert other.get('/dm/unread').json()['count'] == 1
    theirs = other.get('/dm/conversations').json()
    row = next(c for c in theirs if c['id'] == conv['id'])
    assert row['unread'] == 1 and row['peer']['key'] == f"u:{me['id']}" and theirs[0]['pinned']
    thread = other.get(f"/dm/conversations/{conv['id']}/messages").json()
    assert [m['mine'] for m in thread['messages']] == [False]
    assert other.get('/dm/unread').json()['count'] == 0
    # "Visualizzato" for the sender.
    assert client.get(f"/dm/conversations/{conv['id']}/messages").json()['peer_read_at'] >= sent['created_at']

    assert client.put(f"/dm/messages/{sent['id']}/liked", json={'liked': True}).status_code == 422
    assert other.put(f"/dm/messages/{sent['id']}/liked", json={'liked': True}).json() == {'liked': True}

    post = other.post('/feed/posts', json={'place_id': 'caffe', 'body': 'Cappuccino', 'rating': 4, 'photo': PHOTO}).json()
    shared = other.post(f"/dm/conversations/{conv['id']}/messages", json={'post_id': post['id']}).json()
    assert shared['post']['id'] == post['id']
    assert client.get('/dm/conversations').json()[1]['last']['kind'] == 'post'

    stranger, _ = new_client('dm-eve@example.com', name='Eve')
    assert stranger.get(f"/dm/conversations/{conv['id']}/messages").status_code == 404
    assert stranger.post(f"/dm/conversations/{conv['id']}/messages", json={'body': 'x'}).status_code == 404


def test_roam_chat_history_is_saved():
    client.delete('/dm/roam')
    assert client.post('/chat', json=dict(message='caffè', latitude=45.438, longitude=12.336)).status_code == 200
    roam = client.get('/dm/conversations').json()[0]
    assert roam['pinned'] and roam['last']['mine'] is False
    thread = client.get(f"/dm/conversations/{roam['id']}/messages").json()
    assert [m['mine'] for m in thread['messages']] == [True, False]
    assert thread['messages'][1]['places']
    assert client.post(f"/dm/conversations/{roam['id']}/messages", json={'body': 'ciao'}).status_code == 422
