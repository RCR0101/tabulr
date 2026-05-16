String getUserFriendlyError(String rawError) {
  final lower = rawError.toLowerCase();

  if (lower.contains('network') || lower.contains('socketexception') || lower.contains('connection')) {
    return 'Unable to connect to the server. Please check your internet connection and try again.';
  }
  if (lower.contains('permission') || lower.contains('unauthorized') || lower.contains('403')) {
    return 'You don\'t have permission to perform this action. Please sign in again.';
  }
  if (lower.contains('not found') || lower.contains('404')) {
    return 'The requested data could not be found. It may have been moved or deleted.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'The request took too long. Please try again later.';
  }
  if (lower.contains('quota') || lower.contains('rate limit') || lower.contains('429')) {
    return 'Too many requests. Please wait a moment and try again.';
  }
  if (lower.contains('firebase') || lower.contains('firestore')) {
    return 'There was a problem reaching the database. Please try again in a moment.';
  }
  if (lower.contains('parse') || lower.contains('format')) {
    return 'The data received was in an unexpected format. Please try refreshing.';
  }
  if (lower.contains('storage') || lower.contains('disk') || lower.contains('space')) {
    return 'There isn\'t enough storage space available. Please free up some space and try again.';
  }
  if (lower.contains('sign in') || lower.contains('login') || lower.contains('auth')) {
    return 'There was a problem with your sign-in. Please try signing in again.';
  }
  if (lower.contains('saving') || lower.contains('save')) {
    return 'Your changes could not be saved. Please check your connection and try again.';
  }
  if (lower.contains('loading') || lower.contains('load') || lower.contains('fetch')) {
    return 'Failed to load data. Please check your connection and try again.';
  }

  return 'Something went wrong. Please try again, or contact support if the issue persists.';
}
