"""Best-effort, no-key Google Images discovery with place identity checks."""
import html
import ipaddress
import json
import math
import re
import socket
import unicodedata
from html.parser import HTMLParser
from urllib.parse import parse_qs, urlparse

import httpx


def public_url(url):
    try:
        parsed = urlparse(url)
        if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.port not in (None, 443):
            return False
        addresses = socket.getaddrinfo(parsed.hostname, 443, type=socket.SOCK_STREAM)
        return bool(addresses) and all(ipaddress.ip_address(a[4][0]).is_global for a in addresses)
    except (ValueError, OSError):
        return False


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.entities = [], []
        self.ld, self.parts = False, []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'a' and attrs.get('href'):
            self.links.append(attrs['href'])
        if tag == 'script':
            self.ld = attrs.get('type', '').lower() == 'application/ld+json'
            self.parts = []

    def handle_data(self, data):
        if self.ld:
            self.parts.append(data)

    def handle_endtag(self, tag):
        if tag == 'script' and self.ld:
            try:
                self.entities.append(json.loads(''.join(self.parts)))
            except ValueError:
                pass
            self.ld = False


def normalized(value):
    value = unicodedata.normalize('NFKD', str(value).casefold())
    return ' '.join(re.findall(r'[a-z0-9]+', ''.join(c for c in value if not unicodedata.combining(c))))


def entities(value):
    if isinstance(value, list):
        for item in value:
            yield from entities(item)
    elif isinstance(value, dict):
        yield value
        for item in value.values():
            if isinstance(item, (dict, list)):
                yield from entities(item)


def matched_images(data, place):
    """Require the exact named entity and its own coordinates, never page-wide text."""
    photos = []
    for entity in entities(data):
        if normalized(entity.get('name', '')) != normalized(place['name']):
            continue
        geo = entity.get('geo')
        if not isinstance(geo, dict):
            continue
        try:
            lat, lon = float(geo['latitude']), float(geo['longitude'])
            if not (-90 <= lat <= 90 and -180 <= lon <= 180):
                continue
            a, b = math.radians(lat), math.radians(place['latitude'])
            h = math.sin((a-b)/2)**2 + math.cos(a)*math.cos(b)*math.sin(math.radians(lon-place['longitude'])/2)**2
            if 6371 * 2 * math.asin(math.sqrt(min(1, h))) > 0.15:
                continue
        except (KeyError, ValueError, TypeError):
            continue
        images = entity.get('image', [])
        for image in images if isinstance(images, list) else [images]:
            url = image.get('contentUrl') or image.get('url') if isinstance(image, dict) else image
            if isinstance(url, str) and url.startswith('https://'):
                photos.append(url)
    return list(dict.fromkeys(photos))


def candidates(document):
    """Only image/source pairs actually returned by Google Images."""
    page = Page()
    page.feed(document)
    pairs = []
    for link in page.links:
        query = parse_qs(urlparse(html.unescape(link)).query)
        if query.get('imgurl') and query.get('imgrefurl'):
            pairs.append((query['imgurl'][0], query['imgrefurl'][0]))
    # Modern result records encode original image dimensions, then source metadata.
    decoded = html.unescape(document).replace('\\u003d', '=').replace('\\u0026', '&').replace('\\/', '/')
    for record in re.finditer(r'\["(https://[^"\s]+)",\s*\d+,\s*\d+\](.{0,4000}?)\[null,null,"(https://[^"\s]+)"', decoded, re.S):
        pairs.append((record[1], record[3]))
    return list(dict.fromkeys(pairs))[:8]


def fetch_page(client, url):
    # Validate every redirect and bound response size; never read local/private URLs.
    for _ in range(4):
        if not public_url(url):
            return None
        with client.stream('GET', url) as response:
            if response.is_redirect:
                from urllib.parse import urljoin
                url = urljoin(url, response.headers.get('location', ''))
                continue
            response.raise_for_status()
            if 'text/html' not in response.headers.get('content-type', ''):
                return None
            body = bytearray()
            for chunk in response.iter_bytes():
                body.extend(chunk)
                if len(body) > 2_000_000:
                    return None
            return body.decode('utf-8', errors='replace'), url
    return None


def find_photos(place):
    query = f'"{place["name"]}" {place.get("description", "")} {place["latitude"]} {place["longitude"]}'[:600]
    with httpx.Client(timeout=httpx.Timeout(5, connect=2), headers={'User-Agent': 'RoamTraveller/1.0'}, follow_redirects=False) as client:
        response = client.get('https://www.google.com/search', params={'udm': '2', 'q': query, 'hl': 'it'})
        for _ in range(3):
            if not response.is_redirect:
                break
            from urllib.parse import urljoin
            target = urljoin(str(response.url), response.headers.get('location', ''))
            parsed = urlparse(target)
            if parsed.scheme != 'https' or parsed.hostname != 'www.google.com' or parsed.path != '/search':
                return []
            response = client.get(target)
        if response.is_redirect or '/sorry/' in str(response.url):
            return []
        response.raise_for_status()
        photos = []
        sources = {}
        for image, source in candidates(response.text):
            if not public_url(image):
                continue
            try:
                if source not in sources:
                    sources[source] = fetch_page(client, source)
                fetched = sources[source]
                if not fetched:
                    continue
                document, final_url = fetched
                page = Page()
                page.feed(document)
                if image not in matched_images(page.entities, place):
                    continue
                photos.append(dict(url=image, source_url=final_url, author=urlparse(final_url).hostname,
                                   license='Diritti della fonte', title=place['name'], provider='google_images'))
                if len(photos) == 3:
                    break
            except (httpx.HTTPError, ValueError, TypeError):
                continue
        return photos
