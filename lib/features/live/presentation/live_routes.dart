const liveSessionsPath = '/live-sessions';

/// `extra` may carry the session's subject id (for the 403 "go to subject"
/// button) when known from the list.
String liveSessionPath(int id) => '/live-sessions/$id';
