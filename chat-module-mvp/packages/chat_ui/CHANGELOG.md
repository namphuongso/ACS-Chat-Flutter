# Changelog

## 1.0.0

- First production release of `chat_ui`.
- Decomposed `ThreadMessagesNotifier` into 5 specialized modular components (`AvatarCache`, `IdentityResolver`, `SystemMessageEnricher`, `MessageStore`, `RealtimeMessageHandler`).
- Decomposed `ThreadScreen` into modular widgets (`MessageActionSheet`, `ThreadAppBar`, `ThreadSearchBar`).
- Seamless route transitions for modal sheets (`MessageReadersSheet`).
- Full support for `ChatUiConfig` theme and styling customization.
