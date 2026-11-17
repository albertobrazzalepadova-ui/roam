"""Per-user learning: every action becomes a few decayed scores and one short summary.

Nothing here calls an LLM. The memory is compressed deterministically so its size
is bounded (MAX_SUMMARY_CHARS) no matter how long the user has been using Roam.
"""
import json
import logging
import math
import re
import time
from datetime import datetime, timezone

from sqlalchemy import delete, func, select

from database import Session
from models import PlaceCatalog, PostSave, Profile, SocialPost, Trip, UserAffinity, UserEvent, UserMemory, UserPreference

log = logging.getLogger('roam.personalization')

HALF_LIFE_DAYS = 30          # a like is worth half after a month
MAX_EVENTS_PER_USER = 100    # raw log kept only for recency ("last searches")
MAX_KEYS_PER_DIMENSION = 40  # weakest affinities are dropped
MAX_SUMMARY_CHARS = 700      # ~175 tokens in the LLM prompt

CATEGORIES = ['Attrazione', 'Caffè', 'Negozio', 'Ristorante', 'Parco']

# What each action teaches. Values are added to place/category/author scores.
WEIGHTS = {
    'like_post': 3.0, 'unlike_post': -1.5, 'comment_post': 2.0, 'publish_post': 4.0,
    'view_place': 1.0, 'view_person': 1.5, 'search': 1.0, 'chat': 0.5, 'add_trip': 3.0, 'follow': 4.0,
}


def _now() -> float:
    return time.time()


def _decayed(score: float, since: float, now: float) -> float:
    return score * 0.5 ** (max(0.0, now - since) / (HALF_LIFE_DAYS * 86400))


def _norm(value: str) -> str:
    return re.sub(r'\s+', ' ', value.strip().lower())[:200]


def _place(s, place_id):
    row = s.get(PlaceCatalog, place_id)
    return json.loads(row.payload) if row else None


def _bump(s, user_id, dimension, key, label, weight, now):
    if not key:
        return
    row = s.get(UserAffinity, (user_id, dimension, key))
    if row is None:
        row = UserAffinity(user_id=user_id, dimension=dimension, key=key, label=label[:120], score=0.0, hits=0, updated_at=now)
        s.add(row)
    row.score = max(0.0, _decayed(row.score, row.updated_at, now) + weight)
    row.hits += 1
    row.label = label[:120]
    row.updated_at = now


def _prune(s, user_id, dimension):
    keep = select(UserAffinity.key).where(UserAffinity.user_id == user_id, UserAffinity.dimension == dimension) \
        .order_by(UserAffinity.score.desc(), UserAffinity.updated_at.desc()).limit(MAX_KEYS_PER_DIMENSION)
    s.execute(delete(UserAffinity).where(UserAffinity.user_id == user_id, UserAffinity.dimension == dimension,
                                         UserAffinity.key.not_in(keep)))


def _prune_events(s, user_id):
    keep = select(UserEvent.id).where(UserEvent.user_id == user_id).order_by(UserEvent.created_at.desc()).limit(MAX_EVENTS_PER_USER)
    s.execute(delete(UserEvent).where(UserEvent.user_id == user_id, UserEvent.id.not_in(keep)))


def track(kind: str, user_id: int, place_id: str | None = None, post_id: str | None = None,
          author: str | None = None, query: str | None = None, destination: str | None = None,
          rating: int | None = None) -> None:
    """Record one user action. Never raises: learning must not break the app."""
    try:
        _track(kind, user_id, place_id, post_id, author, query, destination, rating)
    except Exception:  # noqa: BLE001
        log.exception('tracking failed for %s', kind)


def _track(kind, user_id, place_id, post_id, author, query, destination, rating):
    now = _now()
    weight = WEIGHTS.get(kind, 1.0)
    if kind == 'review_place' and rating is not None:
        weight = (rating - 3) * 1.5  # 1★ teaches dislike, 5★ strong like
    with Session.begin() as s:
        if s.get(Profile, user_id) is None:
            return
        me = s.get(Profile, user_id).name
        if post_id:
            post = s.get(SocialPost, post_id)
            if post is None:
                return
            place_id = place_id or post.place_id
            if post.user_id != user_id and post.author != me:
                author = author or post.author
        place = _place(s, place_id) if place_id else None
        label = (place or {}).get('name') or author or destination or (query or '')
        s.add(UserEvent(user_id=user_id, kind=kind, target=(place_id or post_id or author or destination or '')[:200] or None,
                        label=label[:120] or None, created_at=now))
        if place:
            _bump(s, user_id, 'place', place_id, place['name'], weight, now)
            if place.get('category') in CATEGORIES:
                _bump(s, user_id, 'category', place['category'], place['category'], weight, now)
        if author and author != me:
            _bump(s, user_id, 'author', author, author, weight if kind != 'review_place' else 0, now)
        if destination:
            _bump(s, user_id, 'destination', _norm(destination), destination.strip(), weight, now)
        if query and kind in ('search', 'chat'):
            _bump(s, user_id, 'search', _norm(query)[:60], query.strip()[:60], weight, now)
            for category in _categories_in(query):
                _bump(s, user_id, 'category', category, category, 0.5, now)
        for dimension in ('place', 'category', 'author', 'destination', 'search'):
            _prune(s, user_id, dimension)
        _prune_events(s, user_id)
        _refresh(s, user_id, now)


KEYWORDS = {
    'Caffè': ['caff', 'bar', 'colazion', 'aperitiv', 'gelat', 'spritz'],
    'Ristorante': ['ristor', 'mangi', 'cena', 'pranzo', 'pizza', 'pesce', 'cucina', 'trattor', 'osteria'],
    'Negozio': ['negoz', 'shopping', 'compr', 'souvenir', 'mercat', 'vintage'],
    'Parco': ['parco', 'giardin', 'natura', 'verde', 'spiaggia', 'passeggi'],
    'Attrazione': ['museo', 'monument', 'chiesa', 'arte', 'storia', 'vista', 'galleria', 'palazzo'],
}


def _categories_in(textvalue: str):
    lowered = textvalue.lower()
    return [c for c, words in KEYWORDS.items() if any(w in lowered for w in words)]


# --- Onboarding ----------------------------------------------------------------

def get_preferences(user_id: int) -> dict:
    with Session() as s:
        p = s.get(UserPreference, user_id)
        if p is None:
            return dict(travel_style='', pace='', budget='', companions='', interests=[], dietary='', notes='', onboarded=False)
        return dict(travel_style=p.travel_style, pace=p.pace, budget=p.budget, companions=p.companions,
                    interests=list(p.interests or []), dietary=p.dietary, notes=p.notes, onboarded=p.onboarded_at is not None)


def save_preferences(values: dict, user_id: int) -> dict:
    now = _now()
    stamp = datetime.now(timezone.utc).isoformat()
    with Session.begin() as s:
        p = s.get(UserPreference, user_id)
        first_time = p is None or p.onboarded_at is None
        if p is None:
            p = UserPreference(user_id=user_id, updated_at=stamp)
            s.add(p)
        for key in ('travel_style', 'pace', 'budget', 'companions', 'dietary', 'notes'):
            setattr(p, key, values.get(key, '').strip())
        p.interests = list(dict.fromkeys(i.strip() for i in values.get('interests', []) if i.strip()))[:12]
        p.onboarded_at = p.onboarded_at or stamp
        p.updated_at = stamp
        # Onboarding gives a warm start so the first chat is already personal.
        if first_time:
            for interest in p.interests:
                if interest in CATEGORIES:
                    _bump(s, user_id, 'category', interest, interest, 3.0, now)
        _refresh(s, user_id, now)
    return get_preferences(user_id)


# --- Compressed memory ----------------------------------------------------------

def _top(s, user_id, dimension, n, now):
    rows = s.scalars(select(UserAffinity).where(UserAffinity.user_id == user_id, UserAffinity.dimension == dimension)).all()
    scored = sorted(((_decayed(r.score, r.updated_at, now), r) for r in rows), key=lambda x: -x[0])
    return [(score, r) for score, r in scored if score >= 0.5][:n]


def _refresh(s, user_id, now):
    summary = _build_summary(s, user_id, now)
    memory = s.get(UserMemory, user_id)
    if memory is None:
        s.add(UserMemory(user_id=user_id, summary=summary, updated_at=now, bootstrapped=0))
    else:
        memory.summary, memory.updated_at = summary, now


def _build_summary(s, user_id, now) -> str:
    parts = []
    p = s.get(UserPreference, user_id)
    if p is not None:
        prefs = [x for x in [p.travel_style and f'stile {p.travel_style}', p.pace and f'ritmo {p.pace}',
                             p.budget and f'budget {p.budget}', p.companions and f'viaggia {p.companions}'] if x]
        if prefs:
            parts.append('Preferenze: ' + ', '.join(prefs) + '.')
        if p.interests:
            parts.append('Interessi: ' + ', '.join(p.interests[:8]) + '.')
        if p.dietary:
            parts.append('Alimentazione: ' + p.dietary[:80] + '.')
        if p.notes:
            parts.append('Note: ' + p.notes[:120] + '.')
    categories = _top(s, user_id, 'category', 5, now)
    if categories:
        total = sum(sc for sc, _ in categories) or 1
        parts.append('Ama: ' + ', '.join(f'{r.label} {round(100 * sc / total)}%' for sc, r in categories) + '.')
    places = _top(s, user_id, 'place', 5, now)
    if places:
        parts.append('Luoghi apprezzati: ' + ', '.join(r.label for _, r in places) + '.')
    authors = _top(s, user_id, 'author', 3, now)
    if authors:
        parts.append('Segue i consigli di: ' + ', '.join(r.label for _, r in authors) + '.')
    destinations = _top(s, user_id, 'destination', 3, now)
    if destinations:
        parts.append('Mete: ' + ', '.join(r.label for _, r in destinations) + '.')
    recent = s.scalars(select(UserEvent.label).where(UserEvent.user_id == user_id, UserEvent.kind.in_(['search', 'chat']),
                                                     UserEvent.label.is_not(None))
                       .order_by(UserEvent.created_at.desc()).limit(3)).all()
    if recent:
        parts.append('Ricerche recenti: ' + '; '.join(dict.fromkeys(x[:40] for x in recent)) + '.')
    summary = ' '.join(parts)
    return summary if len(summary) <= MAX_SUMMARY_CHARS else summary[:MAX_SUMMARY_CHARS - 1].rsplit(' ', 1)[0] + '…'


def memory(user_id: int) -> dict:
    """What the AI knows about the user: shown in the app for transparency."""
    now = _now()
    with Session.begin() as s:
        _refresh(s, user_id, now)  # decay may have changed the ranking since the last action
        m = s.get(UserMemory, user_id)
        cats = _top(s, user_id, 'category', 5, now)
        events = s.scalar(select(func.count()).select_from(UserEvent).where(UserEvent.user_id == user_id))
        return dict(summary=m.summary, categories={r.label: round(sc, 2) for sc, r in cats}, events=events)


def prompt_context(user_id: int) -> str:
    summary = memory(user_id)['summary']
    return summary or 'Nessuna preferenza nota: chiedi cosa ama se utile.'


def category_weights(user_id: int) -> dict[str, float]:
    now = _now()
    with Session() as s:
        return {r.label: sc for sc, r in _top(s, user_id, 'category', 5, now)} | \
               {f'place:{r.key}': sc for sc, r in _top(s, user_id, 'place', MAX_KEYS_PER_DIMENSION, now)}


def top_place_ids(user_id: int, n: int = 8) -> list[str]:
    with Session() as s:
        return [r.key for _, r in _top(s, user_id, 'place', n, _now())]


def rank_places(places: list[dict], user_id: int) -> list[dict]:
    """Nearby places ordered by personal interest, with distance as the tie-breaker."""
    weights = category_weights(user_id)
    if not weights:
        return places
    def score(p):
        return weights.get(p.get('category'), 0) + weights.get('place:' + str(p.get('id')), 0) - 0.3 * math.log1p(p.get('distance') or 0)
    return sorted(places, key=lambda p: (-score(p), p.get('distance') or 0))


def reset(user_id: int) -> None:
    """Forget everything learned; onboarding answers are kept."""
    with Session.begin() as s:
        for model in (UserEvent, UserAffinity):
            s.execute(delete(model).where(model.user_id == user_id))
        _refresh(s, user_id, _now())


def bootstrap_from_history(user_id: int) -> bool:
    """First start only: learn from data that existed before personalization (likes, posts, trips)."""
    with Session() as s:
        if s.get(Profile, user_id) is None or (s.get(UserMemory, user_id) or UserMemory(bootstrapped=0)).bootstrapped:
            return False
        saved = s.scalars(select(PostSave.post_id).where(PostSave.user_id == user_id)).all()
        mine = s.scalars(select(SocialPost.place_id).where(SocialPost.user_id == user_id)).all()
        destinations = s.scalars(select(Trip.destination).where(Trip.user_id == user_id)).all()
    for post_id in saved:
        track('like_post', user_id, post_id=post_id)
    for place_id in mine:
        track('publish_post', user_id, place_id=place_id)
    for destination in destinations:
        track('add_trip', user_id, destination=destination)
    with Session.begin() as s:
        _refresh(s, user_id, _now())
        s.get(UserMemory, user_id).bootstrapped = 1
    return True
