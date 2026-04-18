from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import CheckConstraint, Column, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import relationship

from database import Base


def utcnow():
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(320), nullable=False, unique=True, index=True)
    password_hash = Column(String(255), nullable=True)
    created_at = Column(DateTime, default=utcnow)

    wishlist = relationship("WishlistSnapshot", back_populates="user", uselist=False)


class WishlistSnapshot(Base):
    """Stores the same JSON shape the React app keeps in localStorage (groups + items)."""

    __tablename__ = "wishlist_snapshots"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    groups_json = Column(Text, nullable=False, default="[]")
    items_json = Column(Text, nullable=False, default="[]")
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    user = relationship("User", back_populates="wishlist")


class Friendship(Base):
    """One row per pair with user_low_id < user_high_id to avoid duplicates."""

    __tablename__ = "friendships"
    __table_args__ = (
        UniqueConstraint("user_low_id", "user_high_id", name="uq_friend_pair"),
        CheckConstraint("user_low_id < user_high_id", name="ck_friend_order"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_low_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    user_high_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at = Column(DateTime, default=utcnow)

    user_low = relationship("User", foreign_keys=[user_low_id])
    user_high = relationship("User", foreign_keys=[user_high_id])
