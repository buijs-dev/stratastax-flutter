import 'package:flutter/widgets.dart';

/// The published translations of one locale from a backend (the i18n CMS): message key → text in
/// ICU MessageFormat. Only keys the app knows are used ([OverlayMessages]).
@immutable
final class TranslationBundle {
  const TranslationBundle({required this.locale, required this.messages, this.etag, this.version});

  /// Reads [toJson].
  factory TranslationBundle.fromJson(Map<String, Object?> json) => TranslationBundle(
    locale: _parseLocale(json['locale']! as String),
    messages: (json['messages']! as Map<String, Object?>).cast<String, String>(),
    etag: json['etag'] as String?,
    version: json['version'] as String?,
  );

  final Locale locale;
  final Map<String, String> messages;

  /// Sent as `If-None-Match` on the next fetch.
  final String? etag;

  /// The release that published the bundle, for diagnostics.
  final String? version;

  Map<String, Object?> toJson() => {
    'locale': locale.toLanguageTag(),
    'messages': messages,
    'etag': ?etag,
    'version': ?version,
  };

  static Locale _parseLocale(String tag) {
    final parts = tag.split('-');
    return Locale(parts.first, parts.length > 1 ? parts.last : null);
  }
}

/// Fetches published translations; generated per app for stx.yaml `i18n.remote`.
abstract interface class TranslationSource {
  /// The published bundle of [locale]; null when [etag] is still the published version (or the
  /// backend has nothing for the locale). Throws when the backend cannot be reached or refuses.
  Future<TranslationBundle?> fetch(Locale locale, {String? etag});
}

/// Keeps the last fetched bundle per locale, so the next start shows it before the backend answers;
/// e.g. backed by shared preferences or local storage. Synchronous, like [LocaleStore].
abstract interface class TranslationCache {
  TranslationBundle? read(Locale locale);

  void write(TranslationBundle bundle);
}

/// A [TranslationCache] that lives as long as the app (tests, or no persistent storage).
final class MemoryTranslationCache implements TranslationCache {
  final _bundles = <String, TranslationBundle>{};

  @override
  TranslationBundle? read(Locale locale) => _bundles[locale.toLanguageTag()];

  @override
  void write(TranslationBundle bundle) => _bundles[bundle.locale.toLanguageTag()] = bundle;
}

/// Why a translation from the backend is not used, or could not be fetched.
@immutable
final class TranslationIssue {
  const TranslationIssue(this.kind, this.locale, this.message, {this.key});

  final TranslationIssueKind kind;
  final Locale locale;

  /// Null for [TranslationIssueKind.fetch].
  final String? key;
  final String message;

  @override
  String toString() =>
      'TranslationIssue(${kind.name}, ${locale.toLanguageTag()}${key == null ? '' : ', $key'}: $message)';
}

enum TranslationIssueKind {
  /// The app has no such key; the backend may only translate existing keys.
  unknownKey,

  /// Invalid ICU syntax.
  syntax,

  /// A placeholder the key does not have, or one used with another type.
  arguments,

  /// The backend could not be reached or refused; the built-in (or cached) texts stay.
  fetch,
}
