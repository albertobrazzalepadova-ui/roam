from test_api import client  # first account
from test_api import local_catalog  # noqa: F401  (autouse fixture: Venice catalog, CHAT_PROVIDER=local)
from test_auth import new_client
import groups

VENICE = dict(destination='Venezia', latitude=45.438, longitude=12.336, start_date='2026-12-04', end_date='2026-12-06')


def test_group_trip_discussion_then_plan():
    ada, ada_session = new_client('group-ada@example.com', name='Ada Gruppo')
    ada_key = f"u:{ada_session['user']['id']}"
    outsider, _ = new_client('group-out@example.com', name='Fuori Gruppo')

    assert client.post('/groups', json={**VENICE, 'end_date': '2026-12-01'}).status_code == 422
    assert client.post('/groups', json={**VENICE, 'members': ['n:Demo']}).status_code == 422  # demo travellers cannot reply
    group = client.post('/groups', json={**VENICE, 'members': [ada_key], 'idea': 'Musei e un buon caffè!'})
    assert group.status_code == 201, group.text
    group = group.json()
    gid = group['id']
    assert group['title'] == 'Viaggio a Venezia' and len(group['members']) == 2
    assert [m['kind'] for m in group['messages']] == ['system', 'text']

    # Members see the group with an unread badge; strangers do not see it at all.
    listed = ada.get('/groups').json()
    assert listed[0]['id'] == gid and listed[0]['unread'] == 1
    assert ada.get('/dm/unread').json()['count'] >= 1
    assert outsider.get(f'/groups/{gid}').status_code == 404
    assert outsider.post(f'/groups/{gid}/messages', json={'body': 'ciao'}).status_code == 404

    reply = ada.post(f'/groups/{gid}/messages', json={'body': 'Per me anche un giro in un parco'})
    assert reply.status_code == 201 and reply.json()['mine'] and reply.json()['sender']['key'] == ada_key
    detail = ada.get(f'/groups/{gid}').json()
    assert ada.get('/groups').json()[0]['unread'] == 0  # opening marks it read
    assert set(detail['voices']) == {ada_key, f"u:{client.get('/auth/me').json()['id']}"}

    # ROAM only speaks when asked, and every stop is a real place with coordinates.
    plan = client.post(f'/groups/{gid}/plan')
    assert plan.status_code == 201, plan.text
    message = plan.json()
    assert message['kind'] == 'plan' and message['sender']['key'] == 'roam'
    days = message['plan']['days']
    assert 1 <= len(days) <= 3 and message['plan']['summary']
    stops = [s for d in days for s in d['stops']]
    assert stops and all({'latitude', 'longitude', 'place_id', 'name'} <= set(s) for s in stops)
    assert len({s['place_id'] for s in stops}) == len(stops)
    assert ada.get(f'/groups/{gid}').json()['plan']['days'] == days


def test_group_plan_needs_discussion_and_members_can_join_and_leave():
    bea, bea_session = new_client('group-bea@example.com', name='Bea Gruppo')
    group = client.post('/groups', json=VENICE).json()
    gid = group['id']
    assert client.post(f'/groups/{gid}/plan').status_code == 422  # nothing discussed yet
    added = client.post(f'/groups/{gid}/members', json={'members': [f"u:{bea_session['user']['id']}"]}).json()
    assert len(added['members']) == 2 and added['messages'][-1]['kind'] == 'system'
    assert bea.post(f'/groups/{gid}/leave').status_code == 204
    assert bea.get(f'/groups/{gid}').status_code == 404
    assert client.post(f'/groups/{gid}/leave').status_code == 204
    assert client.get(f'/groups/{gid}').status_code == 404  # last member out: the group is gone


def test_model_answer_is_mapped_to_real_places():
    candidates = [dict(id=f'p{i}', name=f'Luogo {i}', category='Attrazione', latitude=45.43 + i / 1000, longitude=12.33, description='') for i in range(1, 6)]
    plan = groups._parse_plan('Ecco: {"summary": "Ok", "days": [{"title": "Uno", "stops": [{"n": 2, "note": "bello"}, {"n": 99}, {"n": 2}]}]}', candidates, 2)
    assert plan['summary'] == 'Ok' and [s['place_id'] for s in plan['days'][0]['stops']] == ['p2']
    assert groups._parse_plan('non json', candidates, 2) is None
