/// Lightweight, self-contained source-code syntax highlighter.
///
/// Produces a flat list of [CodeToken]s that the UI turns into coloured
/// [TextSpan]s. It intentionally covers the common cases (keywords, strings,
/// comments, numbers, functions, HTML tags/attributes and CSS) rather than
/// being a full language parser, and always falls back to plain text for
/// anything it does not recognise.
library;

/// The kind of syntax a [CodeToken] represents.
enum CodeTokenType {
  plain,
  keyword,
  type,
  function,
  string,
  comment,
  number,
  tag,
  attribute,
}

/// A single highlighted piece of source text.
class CodeToken {
  const CodeToken(this.type, this.text);

  final CodeTokenType type;
  final String text;
}

/// Maps a fenced-code-block language hint to a canonical name recognised by
/// [tokenizeCode]. Unknown hints are returned unchanged (lower-cased).
String normalizeLanguage(String language) {
  final lang = language.trim().toLowerCase();
  const aliases = {
    'py': 'python',
    'python3': 'python',
    'js': 'javascript',
    'node': 'javascript',
    'jsx': 'javascript',
    'mjs': 'javascript',
    'cjs': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'htm': 'html',
    'xml': 'html',
    'svg': 'html',
    'text': 'plain',
    'txt': 'plain',
    'plaintext': 'plain',
    'sh': 'bash',
    'shell': 'bash',
    'zsh': 'bash',
    'yml': 'yaml',
    'md': 'markdown',
    'cs': 'csharp',
    'cpp': 'cpp',
    'c++': 'cpp',
    'c#': 'csharp',
    'rb': 'ruby',
    'golang': 'go',
  };
  return aliases[lang] ?? lang;
}

class _CodeLangConfig {
  const _CodeLangConfig({
    this.keywords = const {},
    this.types = const {},
    this.hashComment = false,
    this.slashComment = false,
    this.htmlMode = false,
    this.cssMode = false,
    this.backtickString = false,
  });

  final Set<String> keywords;
  final Set<String> types;
  final bool hashComment;
  final bool slashComment;
  final bool htmlMode;
  final bool cssMode;
  final bool backtickString;
}

const Set<String> _pythonKeywords = {
  'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', 'break',
  'class', 'continue', 'def', 'del', 'elif', 'else', 'except', 'finally',
  'for', 'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'nonlocal',
  'not', 'or', 'pass', 'raise', 'return', 'try', 'while', 'with', 'yield',
};

const Set<String> _pythonBuiltins = {
  'print', 'len', 'range', 'str', 'int', 'float', 'list', 'dict', 'set',
  'tuple', 'bool', 'type', 'input', 'open', 'super', 'self', 'cls', 'abs',
  'all', 'any', 'bin', 'bytes', 'bytearray', 'callable', 'chr', 'classmethod',
  'complex', 'delattr', 'dir', 'divmod', 'enumerate', 'eval', 'exec', 'filter',
  'format', 'frozenset', 'getattr', 'globals', 'hasattr', 'hash', 'help',
  'hex', 'id', 'isinstance', 'issubclass', 'iter', 'locals', 'map', 'max',
  'memoryview', 'min', 'next', 'object', 'oct', 'ord', 'pow', 'property',
  'repr', 'reversed', 'round', 'setattr', 'slice', 'sorted',
  'staticmethod', 'sum', 'vars', 'zip', 'Exception',
};

const Set<String> _javaKeywords = {
  'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
  'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
  'extends', 'final', 'finally', 'float', 'for', 'goto', 'if', 'implements',
  'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new',
  'package', 'private', 'protected', 'public', 'return', 'short', 'static',
  'strictfp', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws',
  'transient', 'try', 'void', 'volatile', 'while', 'true', 'false', 'null',
};

const Set<String> _javaTypes = {
  'String', 'Integer', 'Boolean', 'Double', 'Float', 'Long', 'Short', 'Byte',
  'Character', 'Object', 'System', 'Math', 'List', 'ArrayList', 'Map',
  'HashMap', 'Set', 'HashSet', 'Collection', 'Arrays', 'Stream', 'Optional',
  'Exception', 'RuntimeException', 'Thread',
};

const Set<String> _jsKeywords = {
  'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
  'default', 'delete', 'do', 'else', 'export', 'extends', 'finally', 'for',
  'function', 'if', 'import', 'in', 'instanceof', 'let', 'new', 'return',
  'super', 'switch', 'this', 'throw', 'try', 'typeof', 'var', 'void', 'while',
  'with', 'yield', 'await', 'async', 'true', 'false', 'null', 'undefined',
  'of',
};

const Set<String> _tsKeywords = {
  'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
  'default', 'delete', 'do', 'else', 'export', 'extends', 'finally', 'for',
  'function', 'if', 'import', 'in', 'instanceof', 'let', 'new', 'return',
  'super', 'switch', 'this', 'throw', 'try', 'typeof', 'var', 'void', 'while',
  'with', 'yield', 'await', 'async', 'true', 'false', 'null', 'undefined',
  'of', 'interface', 'type', 'enum', 'namespace', 'declare', 'readonly',
  'abstract', 'implements', 'static', 'public', 'private', 'protected', 'get',
  'set', 'any', 'unknown', 'never',
};

const Set<String> _jsBuiltins = {
  'console', 'document', 'window', 'Math', 'JSON', 'Object', 'Array', 'String',
  'Number', 'Boolean', 'Date', 'Promise', 'Symbol', 'Map', 'Set', 'RegExp',
  'Error',
};

_CodeLangConfig _configFor(String language) {
  switch (language) {
    case 'python':
      return const _CodeLangConfig(
        keywords: _pythonKeywords,
        types: _pythonBuiltins,
        hashComment: true,
      );
    case 'java':
      return const _CodeLangConfig(
        keywords: _javaKeywords,
        types: _javaTypes,
        slashComment: true,
      );
    case 'javascript':
      return const _CodeLangConfig(
        keywords: _jsKeywords,
        types: _jsBuiltins,
        slashComment: true,
        backtickString: true,
      );
    case 'typescript':
      return const _CodeLangConfig(
        keywords: _tsKeywords,
        types: _jsBuiltins,
        slashComment: true,
        backtickString: true,
      );
    case 'html':
    case 'xml':
      return const _CodeLangConfig(htmlMode: true);
    case 'css':
      return const _CodeLangConfig(cssMode: true, slashComment: true);
    case 'plain':
      return const _CodeLangConfig();
    case 'bash':
    case 'sh':
    case 'shell':
    case 'yaml':
    case 'yml':
      return const _CodeLangConfig(hashComment: true);
    case 'markdown':
      return const _CodeLangConfig();
    default:
      return const _CodeLangConfig(slashComment: true);
  }
}

bool _isAsciiLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isHexDigit(int c) =>
    _isDigit(c) || (c >= 0x61 && c <= 0x66) || (c >= 0x41 && c <= 0x46);
bool _isIdentStart(int c) => _isAsciiLetter(c) || c == 0x5F;
bool _isIdentPart(int c) => _isAsciiLetter(c) || _isDigit(c) || c == 0x5F;

/// Tokenises [code] for the given [language] hint. Never throws; unrecognised
/// constructs are emitted as [CodeTokenType.plain].
List<CodeToken> tokenizeCode(String code, String language) {
  final config = _configFor(normalizeLanguage(language));
  final tokens = <CodeToken>[];
  final n = code.length;
  var i = 0;

  void add(CodeTokenType type, int start, int end) {
    if (end > start) tokens.add(CodeToken(type, code.substring(start, end)));
  }

  while (i < n) {
    final c = code.codeUnitAt(i);

    // Whitespace.
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      final start = i;
      while (i < n) {
        final w = code.codeUnitAt(i);
        if (w != 0x20 && w != 0x09 && w != 0x0A && w != 0x0D) break;
        i++;
      }
      add(CodeTokenType.plain, start, i);
      continue;
    }

    // HTML comment.
    if (config.htmlMode && code.startsWith('<!--', i)) {
      final start = i;
      final end = code.indexOf('-->', i + 4);
      i = end == -1 ? n : end + 3;
      add(CodeTokenType.comment, start, i);
      continue;
    }

    // Block comment.
    if (config.slashComment && code.startsWith('/*', i)) {
      final start = i;
      final end = code.indexOf('*/', i + 2);
      i = end == -1 ? n : end + 2;
      add(CodeTokenType.comment, start, i);
      continue;
    }

    // Line comment.
    if (config.slashComment && code.startsWith('//', i)) {
      final start = i;
      while (i < n && code.codeUnitAt(i) != 0x0A) {
        i++;
      }
      add(CodeTokenType.comment, start, i);
      continue;
    }
    if (config.hashComment && c == 0x23) {
      final start = i;
      while (i < n && code.codeUnitAt(i) != 0x0A) {
        i++;
      }
      add(CodeTokenType.comment, start, i);
      continue;
    }

    // HTML tag (and its attributes).
    if (config.htmlMode && c == 0x3C) {
      final start = i;
      i++;
      // Always keep the opening '<'.
      add(CodeTokenType.tag, start, i);
      if (i < n &&
          (code.codeUnitAt(i) == 0x21 ||
              code.codeUnitAt(i) == 0x2F ||
              _isIdentStart(code.codeUnitAt(i)))) {
        final tagStart = i;
        if (code.codeUnitAt(i) == 0x2F) i++;
        if (i < n && _isIdentStart(code.codeUnitAt(i))) {
          while (i < n && _isIdentPart(code.codeUnitAt(i))) {
            i++;
          }
        }
        add(CodeTokenType.tag, tagStart, i);
        while (i < n && code.codeUnitAt(i) != 0x3E) {
          final a = code.codeUnitAt(i);
          if (_isIdentStart(a)) {
            final attrStart = i;
            while (i < n && _isIdentPart(code.codeUnitAt(i))) {
              i++;
            }
            add(CodeTokenType.attribute, attrStart, i);
          } else if (a == 0x22 || a == 0x27) {
            final q = a;
            final strStart = i;
            i++;
            while (i < n && code.codeUnitAt(i) != q) {
              if (code.codeUnitAt(i) == 0x5C) i++;
              i++;
            }
            if (i < n) i++;
            add(CodeTokenType.string, strStart, i);
          } else {
            add(CodeTokenType.plain, i, i + 1);
            i++;
          }
        }
        if (i < n && code.codeUnitAt(i) == 0x3E) {
          add(CodeTokenType.tag, i, i + 1);
          i++;
        }
      }
      continue;
    }

    // String literal.
    if (c == 0x22 || c == 0x27 || (config.backtickString && c == 0x60)) {
      final q = c;
      final start = i;
      i++;
      while (i < n && code.codeUnitAt(i) != q) {
        if (code.codeUnitAt(i) == 0x5C && i + 1 < n) i++;
        i++;
      }
      if (i < n) i++;
      add(CodeTokenType.string, start, i);
      continue;
    }

    // Number (decimal, hexadecimal and exponent forms).
    if (_isDigit(c) ||
        (c == 0x2E && i + 1 < n && _isDigit(code.codeUnitAt(i + 1)))) {
      final start = i;
      if (c == 0x30 &&
          i + 1 < n &&
          (code.codeUnitAt(i + 1) == 0x78 || code.codeUnitAt(i + 1) == 0x58)) {
        i += 2;
        while (i < n && _isHexDigit(code.codeUnitAt(i))) {
          i++;
        }
      } else {
        while (i < n && (_isDigit(code.codeUnitAt(i)) || code.codeUnitAt(i) == 0x2E)) {
          i++;
        }
        if (i < n && (code.codeUnitAt(i) == 0x65 || code.codeUnitAt(i) == 0x45)) {
          i++;
          if (i < n && (code.codeUnitAt(i) == 0x2B || code.codeUnitAt(i) == 0x2D)) i++;
          while (i < n && _isDigit(code.codeUnitAt(i))) {
            i++;
          }
        }
      }
      add(CodeTokenType.number, start, i);
      continue;
    }

    // Identifier / keyword / built-in type / function call / CSS property.
    if (_isIdentStart(c)) {
      final start = i;
      while (i < n && _isIdentPart(code.codeUnitAt(i))) {
        i++;
      }
      final word = code.substring(start, i);
      var type = CodeTokenType.plain;
      if (config.cssMode && i < n && code.codeUnitAt(i) == 0x3A) {
        type = CodeTokenType.keyword;
      } else if (config.keywords.contains(word)) {
        type = CodeTokenType.keyword;
      } else if (config.types.contains(word)) {
        type = CodeTokenType.type;
      } else if (i < n && code.codeUnitAt(i) == 0x28) {
        type = CodeTokenType.function;
      }
      add(type, start, i);
      continue;
    }

    // CSS hex colour (#fff / #ff0000).
    if (config.cssMode && c == 0x23) {
      final start = i;
      i++;
      while (i < n && _isHexDigit(code.codeUnitAt(i))) {
        i++;
      }
      add(i - start > 1 ? CodeTokenType.number : CodeTokenType.plain, start, i);
      continue;
    }

    add(CodeTokenType.plain, i, i + 1);
    i++;
  }

  return tokens;
}
