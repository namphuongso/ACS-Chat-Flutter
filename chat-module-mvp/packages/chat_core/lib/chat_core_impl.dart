// Barrel export for chat_core internal implementation classes & DTO models
export 'core/data/models/chat_user_model.dart';
export 'core/data/models/chat_member_model.dart';
export 'features/auth_token/data/models/chat_access_token_model.dart';
export 'features/conversation_list/data/models/conversation_model.dart';
export 'features/thread/data/models/message_model.dart';
export 'features/thread/data/models/pinned_message_model.dart';
export 'features/thread/data/models/message_reader_model.dart';
export 'features/thread/data/models/message_resource_model.dart';

export 'features/auth_token/data/datasources/auth_token_remote_datasource_impl.dart';
export 'features/conversation_list/data/datasources/conversation_remote_datasource_impl.dart';
export 'features/thread/data/datasources/message_remote_datasource_impl.dart';
export 'features/thread/data/datasources/websocket_realtime_datasource_impl.dart';
export 'features/auth_token/data/repositories/auth_token_repository_impl.dart';
export 'features/conversation_list/data/repositories/conversation_repository_impl.dart';
export 'features/thread/data/repositories/message_repository_impl.dart';
export 'features/contact/data/datasources/contact_remote_datasource_impl.dart';
export 'features/contact/data/repositories/contact_repository_impl.dart';
