# Personal Discover cards

Discover displays 18 original Rick-and-Morty-style exchanges about recording,
transcription, meetings and everyday computer mishaps. They are fan-written
banter, not dialogue quoted from the show. The sidebar rotates every 30 seconds;
cards can still be copied, and Settings controls visibility (off by default).

Content lives in `Sources/Sotto/Resources/discover-fallback.json`. The service
reads only that bundled data. It never loads old cached upstream content,
requests a remote feed or submits thoughts. The old upstream science/affirmation
cards and network submission feature have been removed.

Focused coverage: `DiscoverServiceTests` and `DiscoverViewModelTests`.
