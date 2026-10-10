import 'dart:async';

/// Why one file in an Acad Drives zip download failed, in words a student can
/// act on. Exactly one of [status] (the HTTP status the file host answered
/// with) or [error] (what the request threw) is given; neither means the file
/// had no usable link to begin with.
String downloadFailureReason({int? status, Object? error, bool insecure = false}) {
  if (insecure) return "Skipped: the link isn't a secure (https) one.";
  if (status != null) {
    return switch (status) {
      401 || 403 => 'Access denied: the file is private or no longer shared.',
      404 || 410 => 'Not found: it was probably moved or deleted from the drive.',
      429 => 'Too many downloads at once. Wait a minute and try again.',
      >= 500 => 'The file host had a problem (error $status). Try again later.',
      _ => 'The file host refused it (error $status).',
    };
  }
  if (error is TimeoutException) return 'Timed out: the file took too long to arrive.';
  if (error != null) {
    // In a browser a failed fetch carries no detail: it is either the network
    // or the host refusing downloads from other sites.
    return "Couldn't reach it: check your connection, or open it directly "
        "(some hosts block downloads from inside Tabulr).";
  }
  return "No download link: this file isn't in Tabulr's copy of the drive yet.";
}
