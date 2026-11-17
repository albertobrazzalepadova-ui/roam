import os
import tempfile
import json
import pytest
os.environ['ROAM_DB'] = tempfile.mktemp(suffix='.db')
from fastapi.testclient import TestClient
from main import app, fetch_local_places as real_fetch_local_places
client = TestClient(app)
# Every API call except /health and /auth/* needs a signed-in user.
SESSION = client.post('/auth/register', json=dict(name='Tester', email='tester@example.com', password='password123')).json()
client.headers['Authorization'] = 'Bearer ' + SESSION['token']

@pytest.fixture(autouse=True)
def local_catalog(monkeypatch):
    import main
    items = [dict(id='rialto', name='Ponte di Rialto', category='Attrazione', latitude=45.438, longitude=12.336, description='Test', symbol='building.columns.fill'), dict(id='caffe', name='Caffè Test', category='Caffè', latitude=45.439, longitude=12.337, description='Test', symbol='cup.and.saucer.fill')]
    with main.db() as c:
        c.executemany('INSERT OR REPLACE INTO place_catalog VALUES(?,?)', [(p['id'],json.dumps(p)) for p in items])
    monkeypatch.setattr(main, 'fetch_local_places', lambda lat, lon: items)
    monkeypatch.delenv('GEMINI_API_KEY', raising=False)
    monkeypatch.setenv('CHAT_PROVIDER', 'local')
    monkeypatch.setenv('IMAGE_PROVIDER', 'commons')
    monkeypatch.setattr(main, '_overpass_down_until', 0.0)


def test_trip_lifecycle_and_dates():
    assert client.post('/trips', json=dict(destination='Roma',start_date='2026-11-03',end_date='2026-11-01')).status_code == 422
    response = client.post('/trips', json=dict(destination='Roma',start_date='2026-11-01',end_date='2026-11-03'))
    assert response.status_code == 201
    assert client.get('/stats').json()['trips'] == 1
    assert client.delete('/trips/' + response.json()['id']).status_code == 204
    assert client.get('/trips').json() == []

def test_comments_and_location():
    assert client.post('/places/missing/comments', json=dict(author='Ada',body='Bello',rating=5)).status_code == 404
    assert client.post('/places/rialto/comments', json=dict(author='Ada',body='Bello',rating=6)).status_code == 422
    assert client.post('/places/rialto/comments', json=dict(author='Ada',body='Bello',rating=5)).status_code == 201
    assert client.get('/places/rialto/comments').json()[0]['body'] == 'Bello'
    places = client.get('/places?latitude=45.438&longitude=12.336').json()
    assert places[0]['id'] == 'rialto'
    assert places[0]['distance'] == 0
    assert 'Caffè' in client.post('/chat',json=dict(message='caffè',latitude=45.438,longitude=12.336)).json()['reply']

def test_profile():
    value = dict(name='Ada',bio='Viaggio!',photo=None)
    assert client.put('/profile',json=value).status_code == 200
    assert client.get('/profile').json() == value

def test_gemini_context_and_errors(monkeypatch):
    import main
    monkeypatch.setenv('CHAT_PROVIDER', 'gemini')
    monkeypatch.setenv('GEMINI_API_KEY', 'test-only-key')
    calls = []
    def respond(request):
        import json
        calls.append(json.loads(request.content))
        assert request.headers['x-goog-api-key'] == 'test-only-key'
        return main.httpx.Response(200, json={'candidates': [{'content': {'parts': [{'text': 'Visita Rialto.'}]}}]})
    original_client = main.httpx.Client
    monkeypatch.setattr(main.httpx, 'Client', lambda **kwargs: original_client(transport=main.httpx.MockTransport(respond), **kwargs))
    response = client.post('/chat', json={'message': 'Cosa visito?', 'latitude': 45.438, 'longitude': 12.336})
    assert response.json()['reply'] == 'Visita Rialto.' and response.json()['mode'] == 'gemini'
    assert [p['id'] for p in response.json()['places']] == ['rialto']  # named in the answer -> banner
    assert 'Ponte di Rialto' in calls[0]['systemInstruction']['parts'][0]['text']
    def limited(request):
        return main.httpx.Response(429, json={})
    monkeypatch.setattr(main.httpx, 'Client', lambda **kwargs: original_client(transport=main.httpx.MockTransport(limited), **kwargs))
    assert client.post('/chat', json={'message': 'Ciao'}).status_code == 503


def test_no_silent_venice_fallback():
    assert client.get('/places').status_code == 422
    assert client.get('/places?latitude=91&longitude=12').status_code == 422
    response = client.post('/chat', json={'message': 'Dove vado?'})
    assert 'Venezia' not in response.json()['reply']
    assert 'Attiva la posizione' in response.json()['reply']


def test_overpass_parsing_cache_and_comments(monkeypatch):
    import main
    main._place_cache.clear()
    requests = []
    original_client = main.httpx.Client
    def respond(request):
        requests.append(request)
        return main.httpx.Response(200, json={'elements': [
            {'type':'node','id':123,'lat':45.438,'lon':12.336,'tags':{'name':'Museo Test','tourism':'museum'}},
            {'type':'way','id':456,'center':{'lat':45.439,'lon':12.337},'tags':{'name':'Caffè Test','amenity':'cafe'}},
            {'type':'node','id':789,'lat':45.44,'lon':12.338,'tags':{'name':'Bottega','shop':'books'}},
            {'type':'node','id':100,'lat':45.44,'lon':12.338,'tags':{'name':'Trattoria','amenity':'restaurant'}},
            {'type':'node','id':101,'lat':45.44,'lon':12.338,'tags':{'name':'Giardino','leisure':'garden'}},
            {'type':'node','id':99,'lat':45.44,'lon':12.338,'tags':{}}
        ]})
    monkeypatch.setattr(main.httpx, 'Client', lambda **kwargs: original_client(transport=main.httpx.MockTransport(respond), **kwargs))
    values = real_fetch_local_places(45.438,12.336)
    assert {p['category'] for p in values} == {'Attrazione','Caffè','Negozio','Ristorante','Parco'}
    assert len(values) == 5
    first_round = len(requests)
    assert 1 <= first_round <= len(main.OVERPASS_URLS)
    assert real_fetch_local_places(45.438,12.336) == values and len(requests) == first_round  # served from cache
    assert client.post('/places/osm-node-123/comments',json={'author':'Ada','body':'Ottimo','rating':5}).status_code == 201
    main._place_cache.clear()
    monkeypatch.setattr(main.httpx, 'Client', lambda **kwargs: original_client(transport=main.httpx.MockTransport(lambda r: main.httpx.Response(503)), **kwargs))
    with pytest.raises(main.HTTPException) as error:
        real_fetch_local_places(45.438,12.336)
    assert error.value.status_code == 503

def test_places_fall_back_to_known_places_and_landmarks(monkeypatch):
    import main
    def down(lat, lon):
        raise main.HTTPException(503, 'down')
    monkeypatch.setattr(main, 'fetch_local_places', down)
    # Venice: places already in the catalog are offered instead of an error.
    venice = client.get('/places', params={'latitude': 45.438, 'longitude': 12.336})
    assert venice.status_code == 200 and 'rialto' in [p['id'] for p in venice.json()]
    # Verona: nothing cached, but the Arena landmark is known.
    verona = client.get('/places', params={'latitude': 45.4384, 'longitude': 10.9916})
    assert verona.status_code == 200 and any(p['id'].startswith('landmark-') for p in verona.json())
    # Open sea: nothing known at all, the outage is reported.
    assert client.get('/places', params={'latitude': 40.0, 'longitude': -30.0}).status_code == 503

def test_apple_place_registration_and_chat_without_overpass(monkeypatch):
    import main
    value = dict(id='apple-' + 'a'*64, name='Museo Test',category='Attrazione',latitude=45.4,longitude=12.3,description='Indirizzo',symbol='building.columns.fill',distance=0.5)
    assert client.post('/places/register',json=value).status_code == 200
    assert client.post('/places/' + value['id'] + '/comments',json={'author':'Ada','body':'Interessante','rating':4}).status_code == 201
    def unavailable(*args):
        raise AssertionError('Overpass must not be called when nearby places are supplied')
    monkeypatch.setattr(main,'fetch_local_places',unavailable)
    response = client.post('/chat',json={'message':'Cosa visito?','latitude':45.4,'longitude':12.3,'nearby_places':[value]})
    assert response.status_code == 200 and 'Museo Test' in response.json()['reply']
    value['latitude'] = 100
    assert client.post('/places/register',json=value).status_code == 422

def test_place_activity_and_photo_are_isolated():
    import base64
    assert client.get('/places/missing/activity').status_code == 404
    assert client.put('/places/rialto/photo',json={'photo':'not-base64'}).status_code == 422
    assert client.put('/places/rialto/photo',json={'photo':base64.b64encode(b'not a jpeg').decode()}).status_code == 422
    photo = base64.b64encode(b'\xff\xd8\xff\xe0test-image-bytes\xff\xd9').decode()
    assert client.put('/places/rialto/photo',json={'photo':photo}).status_code == 200
    assert client.post('/places/caffe/comments',json={'author':'Ada','body':'Una bella pausa','rating':4}).status_code == 201
    first = client.get('/places/rialto/activity').json()
    other = client.get('/places/caffe/activity').json()
    assert first['photo'] == photo
    assert other['photo'] is None and other['rating'] == 4 and other['comments'] == 1
    assert client.get('/places/caffe/comments').json()[0]['body'] == 'Una bella pausa'

def test_landmark_registration_and_comment():
    place = dict(id='landmark-eiffel',name='Torre Eiffel',category='Attrazione',latitude=48.85837,longitude=2.294481,description='Parigi',symbol='building.columns.fill',distance=900)
    assert client.post('/places/register',json=place).status_code == 200
    assert client.post('/places/landmark-eiffel/comments',json={'author':'Ada','body':'Iconica','rating':5}).status_code == 201
    assert client.get('/places/landmark-eiffel/activity').json()['comments'] == 1
    place['latitude']=45
    assert client.post('/places/register',json=place).status_code == 422
    place['id']='apple-'+'b'*64
    assert client.post('/places/register',json=place).status_code == 200
    place['distance']=20051
    assert client.post('/places/register',json=place).status_code == 422

def test_landmark_catalog_matches_ios_and_accepts_all_monuments():
    import main
    from pathlib import Path
    ios_path = Path(__file__).resolve().parents[2] / 'ios/Roam/Assets.xcassets/Landmarks.dataset/catalog.json'
    assert {p['id']: p for p in json.loads(ios_path.read_text())} == main.LANDMARKS
    assert len(main.LANDMARKS) == 16
    for landmark in main.LANDMARKS.values():
        value = dict(id=landmark['id'],name=landmark['name'],category='Attrazione',latitude=landmark['latitude'],longitude=landmark['longitude'],description=landmark['city'],symbol='building.columns.fill',distance=1000)
        assert client.post('/places/register',json=value).status_code == 200
        assert client.get('/places/' + landmark['id'] + '/activity').status_code == 200
    value['id']='landmark-unknown'
    assert client.post('/places/register',json=value).status_code == 422


def test_web_photo_metadata_cache_and_no_coordinates(monkeypatch):
    import main
    calls=[]
    original=main.httpx.Client
    def respond(request):
        calls.append(request)
        assert 'latitude' not in str(request.url) and 'longitude' not in str(request.url)
        return main.httpx.Response(200,json={'query':{'pages':{'1':{'index':1,'title':'File:Ponte di Rialto.jpg','imageinfo':[{'mime':'image/jpeg','thumburl':'https://upload.wikimedia.org/wikipedia/commons/test.jpg','descriptionurl':'https://commons.wikimedia.org/wiki/File:Test.jpg','extmetadata':{'Artist':{'value':'<a>Autore</a>'},'LicenseShortName':{'value':'CC BY-SA 4.0'}}}]}}}})
    monkeypatch.setattr(main.httpx,'Client',lambda **kwargs:original(transport=main.httpx.MockTransport(respond),**kwargs))
    response=client.get('/places/rialto/web-image')
    assert response.status_code == 200
    photo=response.json()['photo']
    assert photo['author']=='Autore' and photo['license']=='CC BY-SA 4.0'
    assert client.get('/places/rialto/web-image').json()==response.json() and len(calls)==1
    assert client.get('/places/missing/web-image').status_code==404

def test_web_photo_rejects_untrusted_url_and_missing_license(monkeypatch):
    import main
    original=main.httpx.Client
    data={'query':{'pages':{'1':{'title':'File:Cafe.jpg','imageinfo':[{'mime':'image/jpeg','thumburl':'https://example.com/fake.jpg','descriptionurl':'https://commons.wikimedia.org/wiki/File:Cafe.jpg','extmetadata':{'LicenseShortName':{'value':'CC BY 4.0'}}}]}}}}
    monkeypatch.setattr(main.httpx,'Client',lambda **kwargs:original(transport=main.httpx.MockTransport(lambda r:main.httpx.Response(200,json=data)),**kwargs))
    assert client.get('/places/caffe/web-image').json()=={'photo':None}


def test_expanded_feed_keeps_categories_and_radius(monkeypatch):
    import main
    items = [dict(id=f'point-{i}', name=f'Luogo {i}', category='Attrazione', latitude=45.438 + i * 0.00001, longitude=12.336, description='Test', symbol='building.columns.fill') for i in range(120)]
    items += [dict(items[0], id='restaurant', category='Ristorante', symbol='fork.knife'), dict(items[0], id='park', category='Parco', symbol='leaf.fill'), dict(items[0], id='far', latitude=46.0)]
    monkeypatch.setattr(main, 'fetch_local_places', lambda lat, lon: items)
    response = client.get('/places?latitude=45.438&longitude=12.336')
    assert response.status_code == 200
    values = response.json()
    assert len(values) == 102
    assert {'restaurant', 'park'} <= {p['id'] for p in values}
    assert all(p['distance'] <= 5 for p in values)
    assert [p['distance'] for p in values] == sorted(p['distance'] for p in values)


def test_wikipedia_photo_fallback_matches_place_coordinates(monkeypatch):
    import main
    with main.db() as c:
        c.execute("DELETE FROM web_photos WHERE place_id='v3:rialto'")
    calls = []
    original = main.httpx.Client
    def respond(request):
        calls.append(request)
        assert '45.438' not in str(request.url) and '12.336' not in str(request.url)
        if request.url.host.endswith('wikipedia.org'):
            return main.httpx.Response(200, json={'query': {'pages': {'1': {'pageimage': 'Historic bridge.jpg', 'coordinates': [{'lat':45.438, 'lon':12.336}]}}}})
        if request.url.params.get('titles'):
            return main.httpx.Response(200, json={'query': {'pages': {'1': {'title':'File:Historic bridge.jpg', 'imageinfo':[{'mime':'image/jpeg', 'thumburl':'https://upload.wikimedia.org/wikipedia/commons/bridge.jpg', 'descriptionurl':'https://commons.wikimedia.org/wiki/File:Historic_bridge.jpg', 'extmetadata':{'Artist':{'value':'Ada'}, 'LicenseShortName':{'value':'CC BY-SA 4.0'}}}]}}}})
        return main.httpx.Response(200, json={})
    monkeypatch.setattr(main.httpx, 'Client', lambda **kw: original(transport=main.httpx.MockTransport(respond), **kw))
    result = client.get('/places/rialto/web-image').json()
    assert result['photo']['title'] == 'Historic bridge.jpg'
    assert result['photos'][0] == result['photo']
    assert len(calls) == 4


def test_wikipedia_photo_rejects_distant_namesake(monkeypatch):
    import main
    with main.db() as c:
        c.execute("DELETE FROM web_photos WHERE place_id='v3:rialto'")
    original = main.httpx.Client
    def respond(request):
        assert not request.url.params.get('titles', '').startswith('File:')
        if request.url.host.endswith('wikipedia.org'):
            return main.httpx.Response(200, json={'query': {'pages': {'1': {'pageimage':'Wrong place.jpg', 'coordinates':[{'lat':40, 'lon':10}]}}}})
        return main.httpx.Response(200, json={})
    monkeypatch.setattr(main.httpx, 'Client', lambda **kw: original(transport=main.httpx.MockTransport(respond), **kw))
    assert client.get('/places/rialto/web-image').json() == {'photo':None}


def test_commons_current_thumbnail_host():
    from main import commons_photos
    page = {'query': {'pages': {'1': {'title':'File:Bridge.jpg', 'imageinfo':[{'mime':'image/jpeg', 'thumburl':'https://thumb.wikimedia.org/wikipedia/commons/thumb/bridge.jpg/960px-bridge.jpg', 'descriptionurl':'https://commons.wikimedia.org/wiki/File:Bridge.jpg', 'extmetadata':{'LicenseShortName':{'value':'CC BY-SA 4.0'}}}]}}}}
    assert len(commons_photos(page)) == 1
    page['query']['pages']['1']['imageinfo'][0]['thumburl'] = 'https://thumb.wikimedia.org.evil.example/bridge.jpg'
    assert commons_photos(page) == []


def test_social_feed_publish_save_comment_and_scope():
    import base64
    photo = base64.b64encode(b'\xff\xd8\xffsocial-test').decode()
    response = client.post('/feed/posts', json={'place_id':'rialto','body':'Una bella scoperta al tramonto','rating':5,'photo':photo})
    assert response.status_code == 201
    post = response.json()
    assert post['photo'] == photo and post['place']['id'] == 'rialto'
    assert post['author'] == client.get('/profile').json()['name']
    assert post['comments'] == 0 and post['saved'] is False and post['mine'] is True
    post_id = post['id']
    nearby = client.post('/feed/query', json={'place_ids':['rialto']}).json()
    assert post_id in {p['id'] for p in nearby['posts']}
    elsewhere = client.post('/feed/query', json={'place_ids':['caffe']}).json()
    assert post_id not in {p['id'] for p in elsewhere['posts']}
    assert client.post('/feed/query', json={}).json()['posts'] == []
    assert client.put(f'/feed/posts/{post_id}/saved',json={'saved':True}).status_code == 200
    saved = client.post('/feed/query',json={'saved_only':True}).json()
    assert post_id in {p['id'] for p in saved['posts']}
    comment = client.post(f'/feed/posts/{post_id}/comments',json={'body':'Che bella luce!','author':'spoofed'})
    assert comment.status_code == 201
    assert comment.json()['author'] == post['author']
    assert comment.json()['mine'] is True and comment.json()['author_key'].startswith('u:') and 'author_photo' in comment.json()
    listed = client.get(f'/feed/posts/{post_id}/comments').json()[0]
    assert listed['body'] == 'Che bella luce!' and listed['mine'] is True and 'user_id' not in listed
    refreshed = client.post('/feed/query',json={'place_ids':['rialto']}).json()['posts']
    assert next(p for p in refreshed if p['id']==post_id)['comments'] == 1
    assert client.put(f'/feed/posts/{post_id}/saved',json={'saved':False}).status_code == 200
    assert post_id not in {p['id'] for p in client.post('/feed/query',json={'saved_only':True}).json()['posts']}
    assert client.post('/feed/posts',json={'place_id':'unknown','body':'Test','rating':5,'photo':photo}).status_code == 404
    assert client.post('/feed/posts',json={'place_id':'rialto','body':'   ','rating':5,'photo':photo}).status_code == 422
    assert client.post('/feed/posts',json={'place_id':'rialto','body':'Test','rating':6,'photo':photo}).status_code == 422
    assert client.post('/feed/posts',json={'place_id':'rialto','body':'Test','rating':5,'photo':'bad'}).status_code == 422
    assert client.post(f'/feed/posts/{post_id}/comments',json={'body':'   '}).status_code == 422
    assert client.post('/feed/posts/missing/comments',json={'body':'Test'}).status_code == 404
    assert client.put('/feed/posts/missing/saved',json={'saved':True}).status_code == 404


def test_social_review_migration_idempotent_and_pagination():
    import main
    review = client.post('/places/caffe/comments',json={'author':'Sara','body':'Ottimo caffè','rating':4}).json()
    legacy_id = 'review-' + review['id']
    first = client.post('/feed/query',json={'place_ids':['caffe']}).json()
    assert legacy_id in {p['id'] for p in first['posts']}
    again = client.post('/feed/query',json={'place_ids':['caffe']}).json()
    assert sum(p['id']==legacy_id for p in again['posts']) == 1
    with main.db() as c:
        for i in range(25):
            c.execute('INSERT INTO social_posts(id,place_id,author,body,rating,photo,created_at,saved) VALUES(?,?,?,?,?,?,?,?)', (f'pagination-{i}','caffe','Sara','Esperienza',4,None,f'2099-01-01T00:00:{i:02d}+00:00',0))
    first = client.post('/feed/query',json={'place_ids':['caffe']}).json()
    second = client.post('/feed/query',json={'place_ids':['caffe'],'offset':20}).json()
    assert len(first['posts']) == 20 and first['has_more'] is True
    assert not ({p['id'] for p in first['posts']} & {p['id'] for p in second['posts']})
    assert client.post('/feed/query',json={'place_ids':['caffe']*501}).status_code == 422
    assert client.post('/feed/query',json={'offset':-1}).status_code == 422


def test_my_posts_delete_and_place_required():
    import base64, main
    photo = base64.b64encode(b'\xff\xd8\xffmine').decode()
    before = client.get('/stats').json()['posts']
    post = client.post('/feed/posts', json={'place_id':'caffe','body':'Il mio cappuccino','rating':4,'photo':photo}).json()
    mine = client.get('/feed/mine').json()['posts']
    assert mine[0]['id'] == post['id'] and mine[0]['place']['id'] == 'caffe'
    assert client.get('/stats').json()['posts'] == before + 1
    review = client.post('/places/caffe/comments',json={'author':'Luca','body':'Buono','rating':4}).json()
    client.post('/feed/query',json={'place_ids':['caffe']})
    assert 'review-' + review['id'] not in {p['id'] for p in client.get('/feed/mine').json()['posts']}
    assert client.delete('/feed/posts/review-' + review['id']).status_code == 403
    client.post(f"/feed/posts/{post['id']}/comments", json={'body':'Bello'})
    assert client.delete(f"/feed/posts/{post['id']}").status_code == 204
    assert client.delete(f"/feed/posts/{post['id']}").status_code == 404
    assert post['id'] not in {p['id'] for p in client.get('/feed/mine').json()['posts']}
    assert post['id'] not in {p['id'] for p in client.post('/feed/query',json={'place_ids':['caffe']}).json()['posts']}
    with main.db() as c:
        assert c.execute('SELECT COUNT(*) FROM social_comments WHERE post_id=?', (post['id'],)).fetchone()[0] == 0
        c.execute("INSERT INTO social_posts(id,place_id,author,body,rating,photo,created_at,saved,mine) VALUES('orphan','gone','Io','Senza luogo',3,NULL,'2100-01-01T00:00:00+00:00',1,1)")
    assert 'orphan' not in {p['id'] for p in client.get('/feed/mine').json()['posts']}
    assert 'orphan' not in {p['id'] for p in client.post('/feed/query',json={'saved_only':True}).json()['posts']}
    assert client.get('/feed/mine?offset=-1').status_code == 422


def test_ollama_context_and_failures(monkeypatch):
    import main
    monkeypatch.setenv('CHAT_PROVIDER', 'ollama')
    monkeypatch.setenv('OLLAMA_MODEL', 'test-model')
    original = main.httpx.Client
    def respond(request):
        payload = json.loads(request.content)
        assert str(request.url) == 'http://127.0.0.1:11434/api/chat'
        assert payload['model'] == 'test-model' and payload['stream'] is False
        assert 'Ponte di Rialto' in payload['messages'][0]['content']
        assert payload['messages'][1]['content'] == 'Cosa visito?'
        return main.httpx.Response(200, json={'message': {'content': 'Visita Rialto.'}})
    monkeypatch.setenv('OLLAMA_BASE_URL', 'http://127.0.0.1:11434')
    monkeypatch.setattr(main.httpx, 'Client', lambda **kw: original(transport=main.httpx.MockTransport(respond), **kw))
    response = client.post('/chat', json={'message':'Cosa visito?', 'latitude':45.438, 'longitude':12.336})
    assert (response.json()['reply'], response.json()['mode']) == ('Visita Rialto.', 'ollama')
    for status, body, expected in [(404, {}, 503), (500, {}, 502), (200, {'message':{'content':''}}, 502)]:
        monkeypatch.setattr(main.httpx, 'Client', lambda **kw: original(transport=main.httpx.MockTransport(lambda r: main.httpx.Response(status, json=body)), **kw))
        assert client.post('/chat', json={'message':'Ciao'}).status_code == expected
    def disconnected(request):
        raise main.httpx.ConnectError('offline', request=request)
    monkeypatch.setattr(main.httpx, 'Client', lambda **kw: original(transport=main.httpx.MockTransport(disconnected), **kw))
    assert client.post('/chat', json={'message':'Ciao'}).status_code == 502


def test_google_images_never_assigns_namesake_photo(monkeypatch):
    import main
    monkeypatch.setenv('IMAGE_PROVIDER', 'google_manual')
    with main.db() as c:
        place = dict(id='namesake', name='Tower Eiffel Caffè', description='Venezia, Campo Test 12', latitude=45.438, longitude=12.336)
        c.execute('INSERT OR REPLACE INTO place_catalog VALUES(?,?)', ('namesake', json.dumps(place)))
    result = client.get('/places/namesake/web-image').json()
    assert result['photo'] is None
    from urllib.parse import urlparse, parse_qs
    query = parse_qs(urlparse(result['search_url']).query)['q'][0]
    assert 'Tower Eiffel Caffè' in query and 'Venezia' in query and '45.438' in query


def test_google_automatic_assignment_cache_and_no_commons(monkeypatch):
    import google_images
    monkeypatch.setenv('IMAGE_PROVIDER', 'google_auto')
    calls = []
    photo = dict(url='https://example.com/cafe.jpg', source_url='https://example.com/cafe', author='example.com', license='Diritti della fonte', title='Caffè Test', provider='google_images')
    def find(place):
        calls.append(place)
        return [photo]
    monkeypatch.setattr(google_images, 'find_photos', find)
    result = client.get('/places/caffe/web-image')
    assert result.status_code == 200 and result.json()['photo'] == photo
    assert client.get('/places/caffe/web-image').json() == result.json()
    assert len(calls) == 1
    assert calls[0]['name'] == 'Caffè Test'
    monkeypatch.setattr(google_images, 'find_photos', lambda place: [])
    assert client.get('/places/rialto/web-image').json() == {'photo': None}

def test_people_search_and_posts():
    import main
    with main.db() as c:
        c.executemany('INSERT OR REPLACE INTO social_posts(id,place_id,author,body,rating,photo,created_at,saved,mine) VALUES(?,?,?,?,?,?,?,?,?)', [
            ('p-giulia-1','rialto','Giulia 100%','Tramonto',5,None,'2026-11-01T10:00:00+00:00',1,0),
            ('p-giulia-2','caffe','Giulia 100%','Colazione',4,None,'2026-11-02T10:00:00+00:00',0,0),
            ('p-marco','rialto','Marco','Ponte',5,None,'2026-11-03T10:00:00+00:00',0,0),
            ('p-ghost','missing-place','Fantasma','Nessun luogo',5,None,'2026-11-04T10:00:00+00:00',0,0)])
    people = client.get('/people', params={'q': 'giulia'}).json()
    assert [p['name'] for p in people] == ['Giulia 100%']
    assert people[0]['posts'] == 2 and people[0]['places'] == 2 and people[0]['mine'] is False
    # LIKE wildcards in the query are matched literally.
    assert client.get('/people', params={'q': '%'}).json()[0]['name'] == 'Giulia 100%'
    assert all(p['name'] != 'Fantasma' for p in client.get('/people').json())
    posts = client.get('/people/posts', params={'name': 'Giulia 100%'}).json()
    assert [p['id'] for p in posts['posts']] == ['p-giulia-2', 'p-giulia-1'] and posts['has_more'] is False
    assert client.get('/people/posts', params={'name': 'Giulia', 'offset': -1}).status_code == 422
    assert client.put('/feed/posts/p-giulia-1/saved', json=dict(saved=True)).status_code == 200
    assert client.get('/stats').json()['saved'] >= 1
