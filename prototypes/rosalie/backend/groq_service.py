from __future__ import annotations

import base64
import os
from typing import Any

import httpx

GROQ_CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_SPEECH_URL = "https://api.groq.com/openai/v1/audio/speech"

DEFAULT_LLM_MODEL = "llama-3.3-70b-versatile"
DEFAULT_TTS_MODEL = "canopylabs/orpheus-v1-english"
DEFAULT_TTS_VOICE = "austin"


def _api_key() -> str:
    return (os.getenv("GROQ_API_KEY") or "").strip()


def groq_configured() -> bool:
    return bool(_api_key())


def _headers() -> dict[str, str]:
    key = _api_key()
    if not key:
        raise RuntimeError("GROQ_API_KEY is not set")
    return {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }


async def chat_completion(system: str, user: str, max_tokens: int = 220) -> str:
    model = (os.getenv("GROQ_LLM_MODEL") or DEFAULT_LLM_MODEL).strip()
    payload: dict[str, Any] = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0.65,
        "max_tokens": max_tokens,
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        r = await client.post(GROQ_CHAT_URL, headers=_headers(), json=payload)
        r.raise_for_status()
        data = r.json()
    try:
        return (data["choices"][0]["message"]["content"] or "").strip()
    except (KeyError, IndexError, TypeError) as e:
        raise RuntimeError("Unexpected Groq chat response shape") from e


async def text_to_speech_wav(text: str) -> bytes:
    """Orpheus English TTS → WAV bytes."""
    if not text.strip():
        raise ValueError("Empty text for TTS")
    model = (os.getenv("GROQ_TTS_MODEL") or DEFAULT_TTS_MODEL).strip()
    voice = (os.getenv("GROQ_TTS_VOICE") or DEFAULT_TTS_VOICE).strip()
    payload = {
        "model": model,
        "input": text[:1200],
        "voice": voice,
        "response_format": "wav",
    }
    async with httpx.AsyncClient(timeout=120.0) as client:
        r = await client.post(GROQ_SPEECH_URL, headers=_headers(), json=payload)
        r.raise_for_status()
        return r.content


def wav_to_data_url(wav: bytes) -> str:
    b64 = base64.b64encode(wav).decode("ascii")
    return f"data:audio/wav;base64,{b64}"
