import os
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from test_api import client, SESSION  # first account: claimed profile 1
from test_api import local_catalog  # noqa: F401  (autouse fixture)
import auth
from main import app


def new_client(email, name='Bea', password='password123'):
    other = TestClient(app)
    response = other.post('/auth/register', json=dict(name=name, email=email, password=password))
    assert response.status_code == 201, response.text
    other.headers['Authorization'] = 'Bearer ' + response.json()['token']
    return other, response.json()


def test_routes_require_a_session_except_health_and_auth():
    anonymous = TestClient(app)
    assert anonymous.get('/health').status_code == 200
    assert anonymous.get('/auth/config').status_code == 200
    for path in ['/trips', '/profile', '/stats', '/me/memory', '/auth/me']:
        assert anonymous.get(path).status_code == 401
    assert anonymous.get('/trips', headers={'Authorization': 'Bearer nope'}).status_code == 401
    assert SESSION['user']['id'] == 1  # the first sign-up inherits the pre-accounts profile


def test_register_login_logout():
    other, session = new_client('Bea@Example.com')
    assert session['user']['email'] == 'bea@example.com' and session['user']['providers'] == ['password']
    assert session['user']['onboarded'] is False
    anonymous = TestClient(app)
    assert anonymous.post('/auth/register', json=dict(name='X', email='bea@example.com', password='password123')).status_code == 409
    assert anonymous.post('/auth/register', json=dict(name='X', email='no-at-sign', password='password123')).status_code == 422
    assert anonymous.post('/auth/register', json=dict(name='X', email='short@example.com', password='short')).status_code == 422
    assert anonymous.post('/auth/login', json=dict(email='bea@example.com', password='wrong-password')).status_code == 401
    assert anonymous.post('/auth/login', json=dict(email='ghost@example.com', password='password123')).status_code == 401
    login = anonymous.post('/auth/login', json=dict(email='BEA@example.com ', password='password123'))
    assert login.status_code == 200
    token = login.json()['token']
    assert anonymous.get('/auth/me', headers={'Authorization': 'Bearer ' + token}).json()['name'] == 'Bea'
    assert anonymous.post('/auth/logout', headers={'Authorization': 'Bearer ' + token}).status_code == 204
    assert anonymous.get('/auth/me', headers={'Authorization': 'Bearer ' + token}).status_code == 401
    assert other.get('/auth/me').status_code == 200  # other sessions stay valid
    with sqlite3.connect(os.environ['ROAM_DB']) as c:
        stored = c.execute("SELECT password_hash FROM profile WHERE email='bea@example.com'").fetchone()[0]
        assert stored.startswith('scrypt$') and 'password123' not in stored
        assert token not in {r[0] for r in c.execute('SELECT token_hash FROM auth_sessions')}


def test_data_is_private_to_each_account():
    import base64
    other, _ = new_client('carla@example.com', name='Carla')
    trip = client.post('/trips', json=dict(destination='Roma', start_date='2026-12-01', end_date='2026-12-03')).json()
    assert trip['id'] not in [t['id'] for t in other.get('/trips').json()]
    assert other.delete('/trips/' + trip['id']).status_code == 404
    photo = base64.b64encode(b'\xff\xd8\xff' + b'0' * 20).decode()
    post = client.post('/feed/posts', json=dict(place_id='rialto', body='Mio', rating=5, photo=photo)).json()
    assert post['mine'] is True
    seen_by_other = other.post('/feed/query', json=dict(place_ids=['rialto'])).json()['posts']
    assert any(p['id'] == post['id'] and p['mine'] is False and p['saved'] is False for p in seen_by_other)
    assert other.delete('/feed/posts/' + post['id']).status_code == 403
    other.put(f"/feed/posts/{post['id']}/saved", json=dict(saved=True))
    assert [p['id'] for p in other.post('/feed/query', json=dict(saved_only=True)).json()['posts']] == [post['id']]
    assert post['id'] not in [p['id'] for p in client.post('/feed/query', json=dict(saved_only=True)).json()['posts']]
    assert other.get('/feed/mine').json()['posts'] == []
    assert other.get('/stats').json() == dict(trips=0, destinations=0, comments=0, posts=0, places=0, saved=1, followers=0, following=0)
    other.put('/me/preferences', json=dict(travel_style='relax'))
    assert 'relax' in other.get('/me/memory').json()['summary']
    assert 'relax' not in client.get('/me/memory').json()['summary']
    assert other.get('/profile').json()['name'] == 'Carla'


def fake_claims(monkeypatch, claims):
    monkeypatch.setattr(auth, 'verify_identity_token', lambda provider, token: claims)


def test_apple_sign_in_creates_then_reuses_account(monkeypatch):
    fake_claims(monkeypatch, dict(sub='apple-123', email='x1@privaterelay.appleid.com', email_verified='true'))
    anonymous = TestClient(app)
    first = anonymous.post('/auth/apple', json=dict(identity_token='t' * 30, name='Dario')).json()
    assert first['user']['name'] == 'Dario' and first['user']['providers'] == ['apple']
    again = anonymous.post('/auth/apple', json=dict(identity_token='t' * 30)).json()
    assert again['user']['id'] == first['user']['id'] and again['token'] != first['token']


def test_google_links_verified_email_and_rejects_bad_tokens(monkeypatch):
    _, session = new_client('elena@example.com', name='Elena')
    fake_claims(monkeypatch, dict(sub='google-9', email='Elena@example.com', email_verified=True, name='Elena G'))
    linked = TestClient(app).post('/auth/google', json=dict(id_token='t' * 30)).json()
    assert linked['user']['id'] == session['user']['id'] and linked['user']['providers'] == ['password', 'google']
    # An unverified email never takes over an existing account.
    fake_claims(monkeypatch, dict(sub='google-10', email='elena@example.com', email_verified=False))
    separate = TestClient(app).post('/auth/google', json=dict(id_token='t' * 30)).json()
    assert separate['user']['id'] != session['user']['id'] and separate['user']['email'] is None
    monkeypatch.undo()
    monkeypatch.delenv('GOOGLE_IOS_CLIENT_ID', raising=False)
    assert TestClient(app).post('/auth/google', json=dict(id_token='not-a-jwt' * 4)).status_code == 401
    monkeypatch.setattr(auth._jwks['google'], 'get_signing_key_from_jwt', lambda token: type('K', (), {'key': 'x'})())
    assert TestClient(app).post('/auth/google', json=dict(id_token='t' * 30)).status_code == 503


def test_config_reports_enabled_methods(monkeypatch):
    monkeypatch.setenv('GOOGLE_IOS_CLIENT_ID', '123-abc.apps.googleusercontent.com')
    monkeypatch.setenv('APPLE_SIGNIN_ENABLED', '1')
    assert TestClient(app).get('/auth/config').json() == {'google_client_id': '123-abc.apps.googleusercontent.com', 'apple': True}
    monkeypatch.delenv('GOOGLE_IOS_CLIENT_ID')
    monkeypatch.delenv('APPLE_SIGNIN_ENABLED')
    assert TestClient(app).get('/auth/config').json() == {'google_client_id': None, 'apple': False}


def test_first_account_inherits_pre_accounts_data():
    path = Path(tempfile.mktemp(suffix='.db'))
    with sqlite3.connect(path) as c:
        c.executescript('''
        CREATE TABLE profile(id INTEGER PRIMARY KEY, name TEXT NOT NULL, bio TEXT NOT NULL, photo TEXT);
        INSERT INTO profile VALUES(1,'Liba','bio',NULL);
        CREATE TABLE trips(id TEXT PRIMARY KEY, destination TEXT NOT NULL, start_date TEXT NOT NULL, end_date TEXT NOT NULL, notes TEXT NOT NULL);
        INSERT INTO trips VALUES('t1','Napoli','2026-01-01','2026-01-02','');
        CREATE TABLE social_posts(id TEXT PRIMARY KEY, place_id TEXT NOT NULL, author TEXT NOT NULL, body TEXT NOT NULL, rating INTEGER NOT NULL, photo TEXT, created_at TEXT NOT NULL, saved INTEGER NOT NULL DEFAULT 0, mine INTEGER NOT NULL DEFAULT 0);
        INSERT INTO social_posts VALUES('p1','x','Liba','b',5,NULL,'2026',1,1);
        INSERT INTO social_posts VALUES('p2','x','Ada','b',5,NULL,'2026',1,0);
        ''')
    script = '''
import json
from fastapi.testclient import TestClient
from main import app
c = TestClient(app)
s = c.post('/auth/register', json=dict(name='Roberto', email='r@example.com', password='password123')).json()
c.headers['Authorization'] = 'Bearer ' + s['token']
second = TestClient(app).post('/auth/register', json=dict(name='Altro', email='a@example.com', password='password123')).json()
print(json.dumps([s['user']['id'], c.get('/trips').json()[0]['destination'], second['user']['id']]))
'''
    out = subprocess.run([sys.executable, '-c', script], check=True, capture_output=True, text=True,
                         cwd=Path(__file__).parents[1], env={**os.environ, 'ROAM_DB': str(path)}).stdout
    assert out.strip().splitlines()[-1] == '[1, "Napoli", 2]'
    with sqlite3.connect(path) as c:
        assert c.execute('SELECT id,user_id FROM social_posts ORDER BY id').fetchall() == [('p1', 1), ('p2', None)]
        assert c.execute('SELECT user_id,post_id FROM post_saves ORDER BY post_id').fetchall() == [(1, 'p1'), (1, 'p2')]
