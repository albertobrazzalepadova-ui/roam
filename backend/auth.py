"""Accounts: email + password, Sign in with Apple, Google Sign-In.

The app receives an opaque bearer token; the server keeps only its SHA-256.
Apple and Google identity tokens are verified locally against their public keys.
"""
import base64
import hashlib
import hmac
import os
import re
import secrets
import time
from datetime import datetime, timezone

import jwt
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select

from database import Session
from models import AuthSession, Profile, UserPreference

router = APIRouter(prefix='/auth', tags=['auth'])

SESSION_DAYS = 90
EMAIL = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
PUBLIC_PATHS = ('/health', '/auth/')

APPLE_ISSUER = 'https://appleid.apple.com'
GOOGLE_ISSUERS = ['https://accounts.google.com', 'accounts.google.com']
_jwks = {
    'apple': jwt.PyJWKClient('https://appleid.apple.com/auth/keys', cache_keys=True, lifespan=86400),
    'google': jwt.PyJWKClient('https://www.googleapis.com/oauth2/v3/certs', cache_keys=True, lifespan=86400),
}


def apple_audiences() -> list[str]:
    return [a.strip() for a in os.environ.get('APPLE_BUNDLE_ID', 'it.robertolibanora.roam').split(',') if a.strip()]


def google_client_ids() -> list[str]:
    return [a.strip() for a in os.environ.get('GOOGLE_IOS_CLIENT_ID', '').split(',') if a.strip()]


def apple_enabled() -> bool:
    return os.environ.get('APPLE_SIGNIN_ENABLED', '').lower() in ('1', 'true', 'yes')


# --- Passwords and tokens -------------------------------------------------------

def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return 'scrypt$' + base64.b64encode(salt).decode() + '$' + base64.b64encode(digest).decode()


def check_password(password: str, stored: str | None) -> bool:
    try:
        scheme, salt, digest = (stored or '').split('$')
        if scheme != 'scrypt':
            return False
        candidate = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt), n=2**14, r=8, p=1, dklen=32)
        return hmac.compare_digest(candidate, base64.b64decode(digest))
    except ValueError:
        return False


_DUMMY_HASH = hash_password(secrets.token_hex(8))  # equalizes login timing for unknown emails


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _issue(s, user: Profile) -> dict:
    token = secrets.token_urlsafe(32)
    now = time.time()
    s.add(AuthSession(token_hash=_token_hash(token), user_id=user.id, created_at=now, expires_at=now + SESSION_DAYS * 86400))
    s.execute(delete(AuthSession).where(AuthSession.user_id == user.id, AuthSession.expires_at < now))
    return {'token': token, 'user': _public(s, user)}


def _public(s, user: Profile) -> dict:
    prefs = s.get(UserPreference, user.id)
    return dict(id=user.id, name=user.name, email=user.email,
                providers=[p for p, v in [('password', user.password_hash), ('apple', user.apple_sub), ('google', user.google_sub)] if v],
                onboarded=bool(prefs and prefs.onboarded_at))


# --- Current user ---------------------------------------------------------------

def current_user(request: Request) -> dict | None:
    """Every route except PUBLIC_PATHS requires `Authorization: Bearer <token>`."""
    if request.url.path.startswith(PUBLIC_PATHS) and request.url.path != '/auth/me':
        return None
    header = request.headers.get('authorization', '')
    token = header[7:].strip() if header.lower().startswith('bearer ') else ''
    if token:
        with Session() as s:
            session = s.get(AuthSession, _token_hash(token))
            if session and session.expires_at > time.time():
                user = s.get(Profile, session.user_id)
                if user:
                    return dict(id=user.id, name=user.name)
    raise HTTPException(401, 'Accedi per continuare', headers={'WWW-Authenticate': 'Bearer'})


def _claimable_first_user(s) -> Profile | None:
    """The pre-accounts profile (with all existing data) goes to the first account created."""
    user = s.get(Profile, 1)
    if user and not (user.email or user.password_hash or user.apple_sub or user.google_sub):
        return user
    return None


def _new_user(s, name: str, email: str | None) -> Profile:
    stamp = datetime.now(timezone.utc).isoformat()
    user = _claimable_first_user(s)
    if user is None:
        user = Profile(name=name or 'Viaggiatore', bio='', photo=None)
        s.add(user)
    elif name:
        user.name = name
    user.email = email
    user.created_at = user.created_at or stamp
    s.flush()
    return user


def _email_taken(s, email: str) -> Profile | None:
    return s.scalar(select(Profile).where(func.lower(Profile.email) == email))


# --- Email + password -------------------------------------------------------------

class RegisterInput(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    email: str = Field(min_length=3, max_length=200)
    password: str = Field(min_length=8, max_length=200)


class LoginInput(BaseModel):
    email: str = Field(min_length=3, max_length=200)
    password: str = Field(min_length=1, max_length=200)


@router.post('/register', status_code=201)
def register(value: RegisterInput):
    email = value.email.strip().lower()
    if not EMAIL.match(email):
        raise HTTPException(422, 'Inserisci un’email valida')
    if not value.name.strip():
        raise HTTPException(422, 'Inserisci un nome')
    with Session.begin() as s:
        if _email_taken(s, email):
            raise HTTPException(409, 'Esiste già un account con questa email. Accedi.')
        user = _new_user(s, value.name.strip(), email)
        user.password_hash = hash_password(value.password)
        return _issue(s, user)


@router.post('/login')
def login(value: LoginInput):
    email = value.email.strip().lower()
    with Session.begin() as s:
        user = _email_taken(s, email)
        if not check_password(value.password, user.password_hash if user else _DUMMY_HASH) or user is None:
            raise HTTPException(401, 'Email o password non corretti')
        return _issue(s, user)


# --- Apple and Google -------------------------------------------------------------

def verify_identity_token(provider: str, token: str) -> dict:
    """Signature, issuer, audience and expiry are all checked."""
    try:
        key = _jwks[provider].get_signing_key_from_jwt(token).key
        if provider == 'apple':
            return jwt.decode(token, key, algorithms=['RS256'], audience=apple_audiences(), issuer=APPLE_ISSUER)
        audiences = google_client_ids()
        if not audiences:
            raise HTTPException(503, 'Accesso con Google non configurato sul server')
        return jwt.decode(token, key, algorithms=['RS256'], audience=audiences, issuer=GOOGLE_ISSUERS)
    except HTTPException:
        raise
    except (jwt.PyJWTError, ValueError) as error:
        raise HTTPException(401, 'Accesso non verificato. Riprova.') from error


def _social_sign_in(provider: str, claims: dict, name: str) -> dict:
    column = Profile.apple_sub if provider == 'apple' else Profile.google_sub
    sub = str(claims.get('sub') or '')
    if not sub:
        raise HTTPException(401, 'Accesso non verificato. Riprova.')
    email = str(claims.get('email') or '').lower() or None
    verified = claims.get('email_verified') in (True, 'true')
    with Session.begin() as s:
        user = s.scalar(select(Profile).where(column == sub))
        if user is None and email and verified:
            existing = _email_taken(s, email)  # same verified email: link to the existing account
            if existing is not None and getattr(existing, column.key) is None:
                user = existing
        if user is None:
            fallback = (email or '').split('@')[0] if not (email or '').endswith('privaterelay.appleid.com') else ''
            user = _new_user(s, name or fallback or 'Viaggiatore', email if verified and not _email_taken(s, email or '') else None)
        setattr(user, column.key, sub)
        return _issue(s, user)


class AppleInput(BaseModel):
    identity_token: str = Field(min_length=20, max_length=8000)
    name: str = Field(default='', max_length=80)  # Apple sends the name only on the first sign-in


class GoogleInput(BaseModel):
    id_token: str = Field(min_length=20, max_length=8000)


@router.post('/apple')
def sign_in_apple(value: AppleInput):
    return _social_sign_in('apple', verify_identity_token('apple', value.identity_token), value.name.strip())


@router.post('/google')
def sign_in_google(value: GoogleInput):
    claims = verify_identity_token('google', value.id_token)
    return _social_sign_in('google', claims, str(claims.get('name') or '').strip()[:80])


# --- Session ------------------------------------------------------------------------

@router.get('/config')
def config():
    """Lets the app show only the sign-in methods this server can verify."""
    ids = google_client_ids()
    return {'google_client_id': ids[0] if ids else None, 'apple': apple_enabled()}


@router.get('/me')
def me(user: dict = Depends(current_user)):
    with Session() as s:
        return _public(s, s.get(Profile, user['id']))


@router.post('/logout', status_code=204)
def logout(request: Request):
    header = request.headers.get('authorization', '')
    if header.lower().startswith('bearer '):
        with Session.begin() as s:
            s.execute(delete(AuthSession).where(AuthSession.token_hash == _token_hash(header[7:].strip())))
