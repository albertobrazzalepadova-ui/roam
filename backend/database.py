"""Database connection and first-start setup."""
import os
import sqlite3
from pathlib import Path

from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.orm import sessionmaker

from models import Base

DB_PATH = Path(os.environ.get('ROAM_DB', Path(__file__).with_name('roam.db')))

engine = create_engine(f'sqlite:///{DB_PATH}', connect_args={'check_same_thread': False})
Session = sessionmaker(engine, expire_on_commit=False)


@event.listens_for(engine, 'connect')
def _sqlite_pragmas(connection, _):
    connection.execute('PRAGMA foreign_keys=ON')


def db():
    """Raw sqlite3 connection, used by the existing hand-written queries."""
    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    return connection


def _add_missing_columns():
    """create_all() never alters existing tables: add new nullable/defaulted columns here."""
    inspector = inspect(engine)
    added = set()
    with engine.begin() as c:
        for table in Base.metadata.sorted_tables:
            existing = {col['name'] for col in inspector.get_columns(table.name)}
            for column in table.columns:
                if column.name in existing:
                    continue
                ddl = f'ALTER TABLE {table.name} ADD COLUMN {column.name} {column.type.compile(engine.dialect)}'
                if column.server_default is not None:
                    ddl += f' NOT NULL DEFAULT {column.server_default.arg.text if hasattr(column.server_default.arg, "text") else repr(column.server_default.arg)}'
                c.execute(text(ddl))
                added.add((table.name, column.name))
        if ('social_posts', 'mine') in added:
            c.execute(text("UPDATE social_posts SET mine=1 WHERE id NOT LIKE 'review-%'"))
    return added


def init_db():
    """Idempotent: creates missing tables on first start and keeps existing data."""
    existing_tables = set(inspect(engine).get_table_names())
    Base.metadata.create_all(engine)
    added = _add_missing_columns()
    with engine.begin() as c:
        for table in Base.metadata.sorted_tables:
            for index in table.indexes:  # create_all only indexes tables it creates
                index.create(c, checkfirst=True)
        c.execute(text("INSERT OR IGNORE INTO profile(id,name,bio,photo) VALUES(1,'Viaggiatore','',NULL)"))
        # Single-user data from before accounts belongs to user 1.
        if ('social_posts', 'user_id') in added:
            c.execute(text('UPDATE social_posts SET user_id=1 WHERE mine=1'))
        if 'post_saves' not in existing_tables:
            c.execute(text("INSERT OR IGNORE INTO post_saves(user_id,post_id,created_at) SELECT 1,id,created_at FROM social_posts WHERE saved=1"))
        if ('comments', 'user_id') in added:
            c.execute(text('UPDATE comments SET user_id=1 WHERE author=(SELECT name FROM profile WHERE id=1)'))
        if ('social_comments', 'user_id') in added:
            c.execute(text('UPDATE social_comments SET user_id=1 WHERE author=(SELECT name FROM profile WHERE id=1)'))
