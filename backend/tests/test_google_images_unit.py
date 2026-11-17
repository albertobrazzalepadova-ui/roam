import unittest
from unittest.mock import patch
import httpx
from google_images import candidates, matched_images, find_photos, public_url

PLACE = dict(name='Tower Eiffel Caffè', latitude=45.438, longitude=12.336, description='Campo Test 12, Venezia')
IMAGE = 'https://photos.example/cafe.jpg'
SOURCE = 'https://cafe.example/venezia'


def entity(lat=45.438, lon=12.336, name='Tower Eiffel Caffè'):
    return {'@type': 'CafeOrCoffeeShop', 'name': name, 'geo': {'latitude': lat, 'longitude': lon}, 'image': IMAGE}


class GoogleImagesTests(unittest.TestCase):
    def test_exact_place_and_own_image(self):
        self.assertEqual(matched_images({'@graph': [entity()]}, PLACE), [IMAGE])

    def test_namesakes_rejected(self):
        self.assertEqual(matched_images(entity(48.858, 2.294), PLACE), [])
        self.assertEqual(matched_images(entity(name='Altro Caffè'), PLACE), [])

    def test_page_mentions_do_not_verify_unrelated_image(self):
        self.assertEqual(matched_images({'name': PLACE['name'], 'image': IMAGE, 'location': {'geo': entity()['geo']}}, PLACE), [])
        self.assertEqual(matched_images({'@graph': [{'name':PLACE['name'], 'geo':entity()['geo']}, {'name':'Torre Eiffel', 'image':IMAGE}]}, PLACE), [])

    def test_invalid_coordinates(self):
        for geo in [None, {}, {'latitude':'x','longitude':12}, {'latitude':float('nan'),'longitude':12}, {'latitude':45.45,'longitude':12.336}]:
            item = entity(); item['geo'] = geo
            self.assertEqual(matched_images(item, PLACE), [])

    def test_google_parsers(self):
        document = '<a href="/imgres?imgurl=https%3A%2F%2Fphotos.example%2Fcafe.jpg&amp;imgrefurl=https%3A%2F%2Fcafe.example%2Fvenezia">Foto</a>'
        self.assertEqual(candidates(document), [(IMAGE, SOURCE)])
        self.assertEqual(candidates(f'[["{IMAGE}",800,600],[],[null,null,"{SOURCE}"]]'), [(IMAGE,SOURCE)])

    def test_private_sources_rejected(self):
        for url in ['http://localhost/a', 'https://127.0.0.1/a', 'https://[::1]/a']:
            self.assertFalse(public_url(url))

    def test_automatic_assignment_and_google_block(self):
        import json
        original = httpx.Client
        search = f'<a href="/imgres?imgurl={IMAGE}&amp;imgrefurl={SOURCE}">Foto</a>'
        calls = []
        def respond(request):
            calls.append(str(request.url))
            if request.url.host == 'www.google.com':
                self.assertIn(PLACE['name'], request.url.params['q'])
                self.assertIn('Venezia', request.url.params['q'])
                return httpx.Response(200, text=search, headers={'content-type':'text/html'})
            return httpx.Response(200, text='<script type="application/ld+json">'+json.dumps(entity())+'</script>', headers={'content-type':'text/html'})
        with patch('google_images.public_url', return_value=True), patch('google_images.httpx.Client', side_effect=lambda **kw: original(transport=httpx.MockTransport(respond), **kw)):
            result = find_photos(PLACE)
        self.assertEqual(result[0]['url'], IMAGE)
        self.assertEqual(result[0]['provider'], 'google_images')
        self.assertEqual(len(calls), 2)
        with patch('google_images.httpx.Client', side_effect=lambda **kw: original(transport=httpx.MockTransport(lambda r: httpx.Response(200, text='<html>Enable JavaScript</html>')), **kw)):
            self.assertEqual(find_photos(PLACE), [])


if __name__ == '__main__':
    unittest.main()
