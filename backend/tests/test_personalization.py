import base64
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

from test_api import client  # shares the temporary DB and the catalog fixture
from test_api import local_catalog  # noqa: F401  (autouse fixture)

import personalization

JPEG = base64.b64encode(b'\xff\xd8\xff' + b'0' * 20).decode()


def setup_function():
    client.delete('/me/memory')


def test_onboarding_warm_start_and_memory_is_bounded():
    assert client.get('/me/preferences').json()['onboarded'] is False
    saved = client.put('/me/preferences', json=dict(travel_style='cultura', pace='lento', interests=['Caffè', 'arte'], dietary='vegetariano')).json()
    assert saved['onboarded'] is True and saved['interests'] == ['Caffè', 'arte']
    memory = client.get('/me/memory').json()
    assert 'cultura' in memory['summary'] and 'vegetariano' in memory['summary']
    assert 'Caffè' in memory['categories']
    for i in range(150):
        client.post('/me/events', json=dict(kind='search', query=f'ricerca lunghissima numero {i} ' + 'x' * 40))
        client.post('/me/events', json=dict(kind='view_place', place_id='rialto'))
    memory = client.get('/me/memory').json()
    assert len(memory['summary']) <= personalization.MAX_SUMMARY_CHARS
    assert memory['events'] <= personalization.MAX_EVENTS_PER_USER
    with personalization.Session() as s:
        from models import UserAffinity
        assert s.query(UserAffinity).filter_by(dimension='search').count() <= personalization.MAX_KEYS_PER_DIMENSION


def test_likes_reviews_and_chat_use_what_was_learned(monkeypatch):
    import main
    assert client.post('/places/{}/comments'.format('caffe'), json=dict(author='Ada', body='Ottimo', rating=5)).status_code == 201
    post = client.post('/feed/posts', json=dict(place_id='caffe', body='Buono', rating=5, photo=JPEG)).json()
    assert client.put(f"/feed/posts/{post['id']}/saved", json=dict(saved=True)).status_code == 200
    memory = client.get('/me/memory').json()
    assert list(memory['categories'])[0] == 'Caffè'
    assert 'Caffè Test' in memory['summary']
    # Without a keyword the local assistant now suggests the favourite category.
    reply = client.post('/chat', json=dict(message='cosa mi consigli?', latitude=45.438, longitude=12.336)).json()['reply']
    assert 'Caffè Test' in reply
    # The LLM prompt carries the compressed profile, not the raw history.
    monkeypatch.setenv('CHAT_PROVIDER', 'gemini')
    monkeypatch.setenv('GEMINI_API_KEY', 'test-only-key')
    calls = []
    def respond(request):
        calls.append(json.loads(request.content))
        return main.httpx.Response(200, json={'candidates': [{'content': {'parts': [{'text': 'Ok.'}]}}]})
    original = main.httpx.Client
    monkeypatch.setattr(main.httpx, 'Client', lambda **kw: original(transport=main.httpx.MockTransport(respond), **kw))
    client.post('/chat', json=dict(message='dove vado?', latitude=45.438, longitude=12.336))
    prompt = calls[0]['systemInstruction']['parts'][0]['text']
    assert 'Profilo e attività' in prompt and 'Caffè Test' in prompt
    first_place = prompt.split('Luoghi vicini, ordinati per interesse:\n', 1)[1].splitlines()[0]
    assert first_place.startswith('- Caffè Test')  # favourite first
    assert 'apple-' not in prompt and '| caffe' not in prompt  # no ids in the prompt
    assert 'Posizione del viaggiatore' in prompt and 'Ora locale' in prompt


def test_one_star_review_teaches_dislike_and_reset_forgets():
    client.post('/places/rialto/comments', json=dict(author='Ada', body='No', rating=1))
    assert 'Attrazione' not in client.get('/me/memory').json()['categories']
    client.post('/me/events', json=dict(kind='view_place', place_id='rialto'))
    assert client.delete('/me/memory').status_code == 204
    assert client.get('/me/memory').json()['events'] == 0
    assert client.post('/me/events', json=dict(kind='view_place', place_id='missing')).status_code == 404


def test_init_db_keeps_legacy_data_and_adds_tables():
    path = Path(tempfile.mktemp(suffix='.db'))
    with sqlite3.connect(path) as c:
        c.executescript('''
        CREATE TABLE profile(id INTEGER PRIMARY KEY, name TEXT NOT NULL, bio TEXT NOT NULL, photo TEXT);
        INSERT INTO profile VALUES(1,'Liba','bio',NULL);
        CREATE TABLE social_posts(id TEXT PRIMARY KEY, place_id TEXT NOT NULL, author TEXT NOT NULL, body TEXT NOT NULL, rating INTEGER NOT NULL, photo TEXT, created_at TEXT NOT NULL, saved INTEGER NOT NULL DEFAULT 0);
        INSERT INTO social_posts VALUES('p1','x','Liba','b',5,NULL,'2026',0);
        INSERT INTO social_posts VALUES('review-1','x','Ada','b',5,NULL,'2026',0);
        ''')
    code = 'import database; database.init_db(); database.init_db()'
    subprocess.run([sys.executable, '-c', code], check=True, cwd=Path(__file__).parents[1], env={**os.environ, 'ROAM_DB': str(path)})
    with sqlite3.connect(path) as c:
        tables = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        assert {'user_preferences', 'user_events', 'user_affinities', 'user_memory', 'trips'} <= tables
        assert c.execute('SELECT name FROM profile').fetchall() == [('Liba',)]
        assert dict(c.execute('SELECT id,mine FROM social_posts').fetchall()) == {'p1': 1, 'review-1': 0}


def test_chat_returns_places_and_posts_for_the_banner():
    post = client.post('/feed/posts', json=dict(place_id='caffe', body='Cappuccino top', rating=5, photo=JPEG)).json()
    result = client.post('/chat', json=dict(message="cosa c'è per me qua?", latitude=45.438, longitude=12.336, area='Venezia')).json()
    assert result['places'] and {'id', 'name', 'latitude', 'longitude', 'distance'} <= set(result['places'][0])
    assert post['id'] in [p['id'] for p in result['posts']] and all(p['photo'] for p in result['posts'])
    # Without location there is nothing to show on a map.
    assert client.post('/chat', json=dict(message='ciao')).json()['places'] == []


def test_chat_cards_survive_map_outage_with_liked_places(monkeypatch):
    import main
    def down(lat, lon):
        raise main.HTTPException(503, 'down')
    monkeypatch.setattr(main, 'fetch_local_places', down)
    post = client.post('/feed/posts', json=dict(place_id='caffe', body='Ottimo', rating=5, photo=JPEG)).json()
    client.put(f"/feed/posts/{post['id']}/saved", json=dict(saved=True))
    # Near the catalog: known places stand in for the map service.
    near = client.post('/chat', json=dict(message="cosa c'è per me qua?", latitude=45.4385, longitude=12.3365)).json()
    assert 'caffe' in [p['id'] for p in near['places']]
    # 22 km away: nothing nearby, the liked place is offered with its real distance.
    far = client.post('/chat', json=dict(message="cosa c'è per me nei dintorni?", latitude=45.63, longitude=12.37)).json()
    caffe = next(p for p in far['places'] if p['id'] == 'caffe')
    assert caffe['distance'] > 15
    assert len([p for p in far['posts'] if p['place_id'] == 'caffe']) <= 2
