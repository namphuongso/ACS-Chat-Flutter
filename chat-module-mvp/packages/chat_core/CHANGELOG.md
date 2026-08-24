# Changelog

## 1.0.0

- First production release of `chat_core`.
- Clean Architecture separation (Domain, Data, DataSources).
- Standardized `metadata` property and parameter naming convention.
- Restricted public barrel export `chat_core.dart` to Domain Entities & UseCases.
- Scoped `sendReadMessage` event targeting in WebSocket realtime data source.
- Multi-format JSON parser support for `MessageReaderModel`.
