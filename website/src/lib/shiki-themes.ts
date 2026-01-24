import type { ThemeRegistration } from 'shiki';

type Palette = {
  bg: string;
  fg: string;
  fgMuted: string;
  fgSubtle: string;
  lineHighlight: string;
  lineBorder: string;
  selection: string;
  selectionInactive: string;
  cursor: string;
  indent: string;
  indentActive: string;
  findMatch: string;
  findMatchHighlight: string;
  bracketBg: string;
  bracketBorder: string;

  comment: string;
  commentDoc: string;
  keyword: string;
  fnDef: string;
  fnCall: string;
  type: string;
  typeParam: string;
  param: string;
  constant: string;
  special: string;
  string: string;
  stringInterpolation: string;
  escape: string;
  regex: string;
  regexOp: string;
  number: string;
  boolean: string;
  punctuation: string;
  operator: string;
  arrow: string;
  tag: string;
  attribute: string;
  decorator: string;
  namespace: string;
  cssId: string;
  link: string;

  error: string;
  warning: string;
  info: string;
  inserted: string;
  deleted: string;
  changed: string;
};

const dark: Palette = {
  bg: '#0d0614',
  fg: '#e8e0f0',
  fgMuted: '#9080a8',
  fgSubtle: '#665880',
  lineHighlight: '#1a0f24',
  lineBorder: '#2a1838',
  selection: '#a855f740',
  selectionInactive: '#a855f720',
  cursor: '#c084fc',
  indent: '#2a1838',
  indentActive: '#4a3860',
  findMatch: '#c084fc40',
  findMatchHighlight: '#c084fc25',
  bracketBg: '#c084fc30',
  bracketBorder: '#c084fc60',

  comment: '#6b5b7a',
  commentDoc: '#7d6d90',
  keyword: '#c084fc',
  fnDef: '#f8f4fc',
  fnCall: '#e2d6f0',
  type: '#f472b6',
  typeParam: '#fb7185',
  param: '#a5b4fc',
  constant: '#fcd34d',
  special: '#f0abfc',
  string: '#86efac',
  stringInterpolation: '#c084fc',
  escape: '#fbbf24',
  regex: '#fda4af',
  regexOp: '#f87171',
  number: '#fdba74',
  boolean: '#5eead4',
  punctuation: '#9080a8',
  operator: '#f9a8d4',
  arrow: '#c084fc',
  tag: '#c084fc',
  attribute: '#a5b4fc',
  decorator: '#facc15',
  namespace: '#c4b5fd',
  cssId: '#facc15',
  link: '#60a5fa',

  error: '#f87171',
  warning: '#fbbf24',
  info: '#60a5fa',
  inserted: '#86efac',
  deleted: '#f87171',
  changed: '#fbbf24',
};

const light: Palette = {
  bg: '#f8f4fc',
  fg: '#1f1528',
  fgMuted: '#6b5880',
  fgSubtle: '#8878a0',
  lineHighlight: '#f0e8f8',
  lineBorder: '#e8e0f0',
  selection: '#9333ea30',
  selectionInactive: '#9333ea18',
  cursor: '#9333ea',
  indent: '#e8e0f0',
  indentActive: '#c0b0d0',
  findMatch: '#9333ea40',
  findMatchHighlight: '#9333ea25',
  bracketBg: '#9333ea30',
  bracketBorder: '#9333ea60',

  comment: '#7c6f94',
  commentDoc: '#6b5e84',
  keyword: '#9333ea',
  fnDef: '#0f0a18',
  fnCall: '#2d1f40',
  type: '#be185d',
  typeParam: '#e11d48',
  param: '#4338ca',
  constant: '#a16207',
  special: '#c026d3',
  string: '#15803d',
  stringInterpolation: '#9333ea',
  escape: '#b45309',
  regex: '#dc2626',
  regexOp: '#b91c1c',
  number: '#c2410c',
  boolean: '#0d9488',
  punctuation: '#6b5880',
  operator: '#db2777',
  arrow: '#9333ea',
  tag: '#9333ea',
  attribute: '#4338ca',
  decorator: '#ca8a04',
  namespace: '#7c3aed',
  cssId: '#ca8a04',
  link: '#1d4ed8',

  error: '#dc2626',
  warning: '#ca8a04',
  info: '#1d4ed8',
  inserted: '#15803d',
  deleted: '#dc2626',
  changed: '#ca8a04',
};

function createTheme(name: string, type: 'dark' | 'light', p: Palette): ThemeRegistration {
  return {
    name,
    displayName: name.charAt(0).toUpperCase() + name.slice(1).replace('-', ' '),
    type,
    colors: {
      'editor.background': p.bg,
      'editor.foreground': p.fg,
      'editorLineNumber.foreground': p.fgSubtle,
      'editorLineNumber.activeForeground': p.keyword,
      'editor.selectionBackground': p.selection,
      'editor.inactiveSelectionBackground': p.selectionInactive,
      'editor.lineHighlightBackground': p.lineHighlight,
      'editor.lineHighlightBorder': p.lineBorder,
      'editorCursor.foreground': p.cursor,
      'editorWhitespace.foreground': p.indent,
      'editorIndentGuide.background': p.indent,
      'editorIndentGuide.activeBackground': p.indentActive,
      'editor.findMatchBackground': p.findMatch,
      'editor.findMatchHighlightBackground': p.findMatchHighlight,
      'editorBracketMatch.background': p.bracketBg,
      'editorBracketMatch.border': p.bracketBorder,
      'editorGutter.background': p.bg,
      'editorError.foreground': p.error,
      'editorWarning.foreground': p.warning,
      'editorInfo.foreground': p.info,
      'diffEditor.insertedTextBackground': p.inserted + '20',
      'diffEditor.removedTextBackground': p.deleted + '20',
    },
    tokenColors: [
      { scope: ['source', 'text'], settings: { foreground: p.fg } },

      // comments
      {
        scope: ['comment', 'comment.line', 'comment.block', 'punctuation.definition.comment'],
        settings: { foreground: p.comment, fontStyle: 'italic' },
      },
      {
        scope: ['comment.block.documentation', 'comment.block.javadoc', 'string.quoted.docstring'],
        settings: { foreground: p.commentDoc, fontStyle: 'italic' },
      },

      // keywords and storage
      {
        scope: [
          'keyword', 'keyword.control', 'keyword.control.conditional', 'keyword.control.loop',
          'keyword.control.flow', 'keyword.control.import', 'keyword.control.export',
          'keyword.control.from', 'keyword.control.return', 'keyword.control.default',
          'keyword.control.trycatch', 'keyword.control.exception', 'keyword.operator.new',
          'keyword.operator.delete', 'keyword.operator.expression', 'keyword.operator.instanceof',
          'keyword.operator.typeof', 'keyword.operator.void', 'keyword.operator.in',
          'keyword.operator.of', 'keyword.operator.sizeof', 'keyword.operator.alignof',
          'keyword.operator.logical', 'keyword.operator.wordlike', 'keyword.other',
          'storage', 'storage.type', 'storage.type.function', 'storage.type.class',
          'storage.type.struct', 'storage.type.enum', 'storage.type.interface',
          'storage.type.trait', 'storage.type.type', 'storage.type.namespace',
          'storage.type.module', 'storage.type.const', 'storage.type.let', 'storage.type.var',
          'storage.modifier', 'storage.modifier.async', 'storage.modifier.static',
          'storage.modifier.public', 'storage.modifier.private', 'storage.modifier.protected',
          'storage.modifier.readonly', 'storage.modifier.abstract', 'storage.modifier.final',
          'storage.modifier.mut', 'storage.modifier.ref',
        ],
        settings: { foreground: p.keyword },
      },

      // functions
      {
        scope: [
          'entity.name.function', 'entity.name.function.method', 'entity.name.function.member',
          'meta.function entity.name.function', 'meta.definition.function entity.name.function',
          'meta.definition.method entity.name.function',
        ],
        settings: { foreground: p.fnDef },
      },
      {
        scope: [
          'meta.function-call', 'meta.function-call entity.name.function', 'support.function',
          'support.function.builtin', 'support.function.magic', 'support.function.console',
          'entity.name.function.call', 'variable.function',
        ],
        settings: { foreground: p.fnCall },
      },

      // types
      {
        scope: [
          'entity.name.type', 'entity.name.type.class', 'entity.name.type.struct',
          'entity.name.type.enum', 'entity.name.type.interface', 'entity.name.type.trait',
          'entity.name.type.type-alias', 'entity.name.type.type-parameter', 'entity.name.class',
          'entity.other.inherited-class', 'support.type', 'support.type.builtin',
          'support.type.primitive', 'support.class', 'support.class.builtin',
          'meta.type.annotation entity.name.type',
        ],
        settings: { foreground: p.type },
      },
      {
        scope: [
          'entity.name.type.parameter', 'meta.type.parameters entity.name.type',
          'punctuation.definition.typeparameters',
        ],
        settings: { foreground: p.typeParam },
      },

      // variables
      {
        scope: [
          'variable', 'variable.other', 'variable.other.readwrite', 'variable.other.local',
          'variable.other.object', 'variable.other.property', 'meta.object-literal.key',
        ],
        settings: { foreground: p.fg },
      },
      {
        scope: [
          'variable.parameter', 'variable.parameter.function', 'meta.parameter',
          'meta.function.parameters variable', 'entity.name.variable.parameter',
        ],
        settings: { foreground: p.param, fontStyle: 'italic' },
      },
      {
        scope: [
          'variable.other.constant', 'variable.other.enummember', 'entity.name.constant',
          'constant.other', 'constant.other.caps', 'meta.enum constant.other',
        ],
        settings: { foreground: p.constant },
      },
      {
        scope: [
          'variable.language', 'variable.language.this', 'variable.language.self',
          'variable.language.super', 'variable.language.special',
        ],
        settings: { foreground: p.special, fontStyle: 'italic' },
      },

      // strings
      {
        scope: [
          'string', 'string.quoted', 'string.quoted.single', 'string.quoted.double',
          'string.quoted.triple', 'string.quoted.other', 'string.template', 'string.unquoted',
          'punctuation.definition.string.begin', 'punctuation.definition.string.end',
        ],
        settings: { foreground: p.string },
      },
      {
        scope: [
          'string.template meta.embedded', 'string.template punctuation.definition.template-expression',
          'meta.template.expression', 'punctuation.definition.interpolation', 'punctuation.section.embedded',
        ],
        settings: { foreground: p.stringInterpolation },
      },
      {
        scope: ['constant.character.escape', 'constant.character.escaped', 'constant.other.placeholder', 'string constant.other.placeholder'],
        settings: { foreground: p.escape },
      },

      // regex
      {
        scope: ['string.regexp', 'string.regex', 'punctuation.definition.string.regexp'],
        settings: { foreground: p.regex },
      },
      {
        scope: [
          'keyword.operator.quantifier.regexp', 'keyword.control.anchor.regexp',
          'keyword.operator.or.regexp', 'constant.character.escape.regexp',
          'constant.other.character-class.regexp', 'punctuation.definition.character-class.regexp',
          'punctuation.definition.group.regexp',
        ],
        settings: { foreground: p.regexOp },
      },

      // numbers and booleans
      {
        scope: [
          'constant.numeric', 'constant.numeric.integer', 'constant.numeric.float',
          'constant.numeric.hex', 'constant.numeric.octal', 'constant.numeric.binary',
          'constant.numeric.decimal',
        ],
        settings: { foreground: p.number },
      },
      {
        scope: [
          'constant.language', 'constant.language.boolean', 'constant.language.true',
          'constant.language.false', 'constant.language.null', 'constant.language.undefined',
          'constant.language.nil', 'constant.language.none',
        ],
        settings: { foreground: p.boolean },
      },

      // punctuation and operators
      {
        scope: [
          'punctuation', 'punctuation.definition', 'punctuation.separator',
          'punctuation.separator.comma', 'punctuation.separator.period',
          'punctuation.separator.colon', 'punctuation.terminator', 'punctuation.terminator.statement',
          'punctuation.accessor', 'punctuation.accessor.period', 'punctuation.accessor.arrow',
          'punctuation.accessor.optional', 'meta.brace', 'meta.brace.round', 'meta.brace.square',
          'meta.brace.curly', 'punctuation.definition.block', 'punctuation.definition.parameters',
          'punctuation.definition.arguments', 'punctuation.section', 'punctuation.section.block',
          'punctuation.section.brackets', 'punctuation.section.parens',
        ],
        settings: { foreground: p.punctuation },
      },
      {
        scope: [
          'keyword.operator', 'keyword.operator.assignment', 'keyword.operator.assignment.compound',
          'keyword.operator.arithmetic', 'keyword.operator.bitwise', 'keyword.operator.comparison',
          'keyword.operator.relational', 'keyword.operator.logical', 'keyword.operator.ternary',
          'keyword.operator.spread', 'keyword.operator.rest', 'keyword.operator.type',
          'keyword.operator.optional',
        ],
        settings: { foreground: p.operator },
      },
      {
        scope: ['keyword.operator.arrow', 'storage.type.function.arrow', 'punctuation.definition.arrow'],
        settings: { foreground: p.arrow },
      },

      // html/xml/jsx
      {
        scope: [
          'entity.name.tag', 'entity.name.tag.html', 'entity.name.tag.xml',
          'entity.name.tag.jsx', 'entity.name.tag.tsx', 'meta.tag.sgml',
          'punctuation.definition.tag', 'punctuation.definition.tag.begin',
          'punctuation.definition.tag.end',
        ],
        settings: { foreground: p.tag },
      },
      {
        scope: [
          'punctuation.definition.tag.html', 'punctuation.definition.tag.begin.html',
          'punctuation.definition.tag.end.html',
        ],
        settings: { foreground: p.punctuation },
      },
      {
        scope: [
          'entity.other.attribute-name', 'entity.other.attribute-name.html',
          'entity.other.attribute-name.jsx', 'entity.other.attribute-name.tsx',
          'entity.other.attribute-name.localname',
        ],
        settings: { foreground: p.attribute, fontStyle: 'italic' },
      },
      { scope: ['string.quoted.single.html', 'string.quoted.double.html'], settings: { foreground: p.string } },

      // decorators
      {
        scope: [
          'meta.decorator', 'meta.attribute', 'entity.name.function.decorator',
          'entity.name.function.macro', 'punctuation.definition.annotation',
          'punctuation.decorator', 'storage.type.annotation', 'meta.annotation',
          'meta.annotation.identifier',
        ],
        settings: { foreground: p.decorator },
      },

      // namespaces
      {
        scope: [
          'entity.name.namespace', 'entity.name.module', 'entity.name.type.module',
          'entity.name.scope-resolution', 'support.other.namespace', 'meta.path',
        ],
        settings: { foreground: p.namespace },
      },
      {
        scope: ['meta.import variable.other', 'meta.import entity.name', 'variable.other.alias'],
        settings: { foreground: p.param },
      },

      // css
      {
        scope: ['entity.name.tag.css', 'entity.name.tag.scss', 'entity.name.tag.less'],
        settings: { foreground: p.tag },
      },
      {
        scope: ['entity.other.attribute-name.class.css', 'entity.other.attribute-name.class.scss', 'entity.other.attribute-name.class.less'],
        settings: { foreground: p.type },
      },
      {
        scope: ['entity.other.attribute-name.id.css', 'entity.other.attribute-name.id.scss', 'entity.other.attribute-name.id.less'],
        settings: { foreground: p.cssId },
      },
      {
        scope: ['entity.other.attribute-name.pseudo-class.css', 'entity.other.attribute-name.pseudo-element.css'],
        settings: { foreground: p.special, fontStyle: 'italic' },
      },
      {
        scope: ['support.type.property-name', 'support.type.property-name.css', 'meta.property-name', 'meta.property-name.css'],
        settings: { foreground: p.param },
      },
      {
        scope: ['support.constant.property-value', 'support.constant.color', 'constant.other.color', 'constant.other.color.rgb-value', 'meta.property-value'],
        settings: { foreground: p.string },
      },
      {
        scope: ['keyword.other.unit', 'keyword.other.unit.css', 'constant.numeric.css'],
        settings: { foreground: p.number },
      },

      // json/yaml
      {
        scope: ['support.type.property-name.json', 'string.json support.type.property-name'],
        settings: { foreground: p.param },
      },
      {
        scope: ['entity.name.tag.yaml', 'punctuation.definition.anchor.yaml'],
        settings: { foreground: p.keyword },
      },

      // markdown
      {
        scope: ['markup.heading', 'entity.name.section', 'heading.1', 'heading.2', 'heading.3'],
        settings: { foreground: p.keyword, fontStyle: 'bold' },
      },
      { scope: ['punctuation.definition.heading.markdown'], settings: { foreground: p.punctuation } },
      { scope: ['markup.bold', 'punctuation.definition.bold'], settings: { foreground: p.type, fontStyle: 'bold' } },
      { scope: ['markup.italic', 'punctuation.definition.italic'], settings: { foreground: p.special, fontStyle: 'italic' } },
      { scope: ['markup.strikethrough'], settings: { foreground: p.comment, fontStyle: 'strikethrough' } },
      { scope: ['markup.inline.raw', 'markup.raw.block', 'markup.fenced_code'], settings: { foreground: p.string } },
      { scope: ['markup.quote', 'punctuation.definition.quote'], settings: { foreground: p.punctuation, fontStyle: 'italic' } },
      { scope: ['markup.list', 'punctuation.definition.list'], settings: { foreground: p.type } },
      { scope: ['markup.underline.link', 'string.other.link'], settings: { foreground: p.link } },
      { scope: ['markup.inserted', 'punctuation.definition.inserted'], settings: { foreground: p.inserted } },
      { scope: ['markup.deleted', 'punctuation.definition.deleted'], settings: { foreground: p.deleted } },
      { scope: ['markup.changed'], settings: { foreground: p.changed } },

      // invalid
      { scope: ['invalid', 'invalid.illegal'], settings: { foreground: p.error, fontStyle: 'underline' } },
      { scope: ['invalid.deprecated'], settings: { foreground: p.warning, fontStyle: 'strikethrough' } },

      // shell
      { scope: ['variable.other.normal.shell', 'variable.other.positional.shell'], settings: { foreground: p.param } },
      { scope: ['string.interpolated.dollar.shell', 'string.interpolated.backtick.shell'], settings: { foreground: p.string } },

      // sql
      { scope: ['keyword.other.DML.sql', 'keyword.other.DDL.sql'], settings: { foreground: p.keyword } },

      // make
      { scope: ['variable.other.makefile', 'entity.name.function.target.makefile'], settings: { foreground: p.type } },

      // rust
      {
        scope: ['entity.name.type.lifetime.rust', 'punctuation.definition.lifetime.rust'],
        settings: { foreground: p.decorator, fontStyle: 'italic' },
      },
      { scope: ['keyword.operator.borrow.rust', 'keyword.operator.dereference.rust'], settings: { foreground: p.operator } },

      // go
      { scope: ['entity.name.package.go', 'entity.name.import.go'], settings: { foreground: p.namespace } },
    ],
  };
}

export const ferruleDark = createTheme('ferrule-dark', 'dark', dark);
export const ferruleLight = createTheme('ferrule-light', 'light', light);
