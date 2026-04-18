"""
Wikipedia (MediaWiki extracts API) and Wikidata descriptions for OSM objects that
carry wikipedia / wikidata tags — no API keys.

https://meta.wikimedia.org/wiki/User-Agent_policy
"""

from __future__ import annotations

import httpx

UA = {
    "User-Agent": (
        "OrbitTripSyncPrototype/0.2 "
        "(https://github.com/CSEN-SCU/csen-174-s26-team-project-tripsync; university coursework)"
    )
}
MAX_CHARS = 480


def wikipedia_summary(wikipedia_tag: str, client: httpx.Client) -> str | None:
    """
    OSM `wikipedia` / `wikipedia:en` format, e.g. `en:Golden_Gate_Bridge` or `Golden_Gate_Bridge`.
    Uses the MediaWiki `extracts` API (not REST summary — REST often 403s minimal clients).
    """
    wikipedia_tag = (wikipedia_tag or "").strip()
    if not wikipedia_tag:
        return None
    if ":" in wikipedia_tag:
        lang, title = wikipedia_tag.split(":", 1)
        lang = (lang or "en").strip()[:12] or "en"
        title = title.strip()
    else:
        lang, title = "en", wikipedia_tag.strip()
    if not title:
        return None

    title = title.replace("_", " ")
    url = f"https://{lang}.wikipedia.org/w/api.php"
    params = {
        "action": "query",
        "titles": title,
        "prop": "extracts",
        "exintro": "true",
        "explaintext": "true",
        "format": "json",
    }
    try:
        r = client.get(url, params=params, headers=UA, timeout=4.0)
        if r.status_code != 200:
            return None
        data = r.json()
        pages = (data.get("query") or {}).get("pages") or {}
        for _pid, page in pages.items():
            if page.get("missing"):
                continue
            extract = page.get("extract")
            if isinstance(extract, str) and len(extract.strip()) > 40:
                return extract.strip()
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        return None
    return None


def wikidata_description(qid: str, client: httpx.Client) -> str | None:
    """English Wikidata description when Wikipedia is missing."""
    qid = (qid or "").strip()
    if not qid.startswith("Q"):
        return None
    url = f"https://www.wikidata.org/wiki/Special:EntityData/{qid}.json"
    try:
        r = client.get(url, headers=UA, timeout=4.0)
        if r.status_code != 200:
            return None
        data = r.json()
        ent = (data.get("entities") or {}).get(qid) or {}
        descs = ent.get("descriptions") or {}
        en = descs.get("en") or {}
        val = en.get("value")
        if isinstance(val, str) and len(val.strip()) > 8:
            return val.strip()
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        return None
    return None


def _lookup_row(item: tuple) -> tuple:
    row, wiki, qid = item
    with httpx.Client(timeout=5.0) as client:
        text = None
        if wiki:
            text = wikipedia_summary(wiki, client)
        if not text and qid:
            text = wikidata_description(qid, client)
    return row, text


def enrich_poi_descriptions(rows: list[dict], max_lookups: int = 12) -> None:
    """
    Replace short_description with Wikipedia extract or Wikidata description when available.
    Mutates rows in place; strips internal _wiki / _qid keys from every row.
    """
    from concurrent.futures import ThreadPoolExecutor, as_completed

    work: list[tuple] = []
    for row in rows:
        wiki = row.pop("_wiki", None)
        qid = row.pop("_qid", None)
        if wiki or qid:
            work.append((row, wiki, qid))

    chunk = work[:max_lookups]
    if not chunk:
        return

    with ThreadPoolExecutor(max_workers=5) as pool:
        futures = [pool.submit(_lookup_row, item) for item in chunk]
        for fut in as_completed(futures):
            try:
                row, text = fut.result()
                if text:
                    row["short_description"] = text[:MAX_CHARS] + (
                        "…" if len(text) > MAX_CHARS else ""
                    )
            except Exception:
                pass
