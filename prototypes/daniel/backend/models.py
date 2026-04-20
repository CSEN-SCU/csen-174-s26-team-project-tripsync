from sqlalchemy import Column, Integer, String, Float, Text, DateTime
from datetime import datetime, timezone
from database import Base


class POI(Base):
    __tablename__ = "pois"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False)
    lat = Column(Float, nullable=False)
    lng = Column(Float, nullable=False)
    category = Column(String(50), nullable=False)
    short_description = Column(Text, nullable=False)
    tags = Column(String(500), default="")
    image_url = Column(String(500), default="")


class ConversationLog(Base):
    __tablename__ = "conversation_logs"

    id = Column(Integer, primary_key=True, index=True)
    poi_id = Column(Integer, nullable=True)
    role = Column(String(20), nullable=False)
    content = Column(Text, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class UserPreference(Base):
    __tablename__ = "user_preferences"

    id = Column(Integer, primary_key=True, index=True)
    interest = Column(String(100), nullable=False, unique=True)
    active = Column(Integer, default=1)
