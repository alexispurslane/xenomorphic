use indexmap::IndexMap;
use serde::Deserialize;
use strum::EnumIter;

#[derive(Debug, PartialEq, Eq, Deserialize)]
#[serde(untagged)]
pub enum VsCodeTokenScope {
    One(String),
    Many(Vec<String>),
}

#[derive(Debug, Deserialize)]
pub struct VsCodeTokenColor {
    pub name: Option<String>,
    pub scope: Option<VsCodeTokenScope>,
    pub settings: VsCodeTokenColorSettings,
}

#[derive(Debug, Deserialize)]
pub struct VsCodeTokenColorSettings {
    pub foreground: Option<String>,
    pub background: Option<String>,
    #[serde(rename = "fontStyle")]
    pub font_style: Option<String>,
}

#[derive(Debug, PartialEq, Copy, Clone, EnumIter)]
pub enum XenomorphicSyntaxToken {
    Attribute,
    Boolean,
    Comment,
    CommentDoc,
    Constant,
    Constructor,
    Embedded,
    Emphasis,
    EmphasisStrong,
    Enum,
    Function,
    Hint,
    Keyword,
    Label,
    LinkText,
    LinkUri,
    Number,
    Operator,
    Predictive,
    Preproc,
    Primary,
    Property,
    Punctuation,
    PunctuationBracket,
    PunctuationDelimiter,
    PunctuationListMarker,
    PunctuationSpecial,
    String,
    StringEscape,
    StringRegex,
    StringSpecial,
    StringSpecialSymbol,
    Tag,
    TextLiteral,
    Title,
    Type,
    Variable,
    VariableSpecial,
    Variant,
}

impl std::fmt::Display for XenomorphicSyntaxToken {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{}",
            match self {
                XenomorphicSyntaxToken::Attribute => "attribute",
                XenomorphicSyntaxToken::Boolean => "boolean",
                XenomorphicSyntaxToken::Comment => "comment",
                XenomorphicSyntaxToken::CommentDoc => "comment.doc",
                XenomorphicSyntaxToken::Constant => "constant",
                XenomorphicSyntaxToken::Constructor => "constructor",
                XenomorphicSyntaxToken::Embedded => "embedded",
                XenomorphicSyntaxToken::Emphasis => "emphasis",
                XenomorphicSyntaxToken::EmphasisStrong => "emphasis.strong",
                XenomorphicSyntaxToken::Enum => "enum",
                XenomorphicSyntaxToken::Function => "function",
                XenomorphicSyntaxToken::Hint => "hint",
                XenomorphicSyntaxToken::Keyword => "keyword",
                XenomorphicSyntaxToken::Label => "label",
                XenomorphicSyntaxToken::LinkText => "link_text",
                XenomorphicSyntaxToken::LinkUri => "link_uri",
                XenomorphicSyntaxToken::Number => "number",
                XenomorphicSyntaxToken::Operator => "operator",
                XenomorphicSyntaxToken::Predictive => "predictive",
                XenomorphicSyntaxToken::Preproc => "preproc",
                XenomorphicSyntaxToken::Primary => "primary",
                XenomorphicSyntaxToken::Property => "property",
                XenomorphicSyntaxToken::Punctuation => "punctuation",
                XenomorphicSyntaxToken::PunctuationBracket => "punctuation.bracket",
                XenomorphicSyntaxToken::PunctuationDelimiter => "punctuation.delimiter",
                XenomorphicSyntaxToken::PunctuationListMarker => "punctuation.list_marker",
                XenomorphicSyntaxToken::PunctuationSpecial => "punctuation.special",
                XenomorphicSyntaxToken::String => "string",
                XenomorphicSyntaxToken::StringEscape => "string.escape",
                XenomorphicSyntaxToken::StringRegex => "string.regex",
                XenomorphicSyntaxToken::StringSpecial => "string.special",
                XenomorphicSyntaxToken::StringSpecialSymbol => "string.special.symbol",
                XenomorphicSyntaxToken::Tag => "tag",
                XenomorphicSyntaxToken::TextLiteral => "text.literal",
                XenomorphicSyntaxToken::Title => "title",
                XenomorphicSyntaxToken::Type => "type",
                XenomorphicSyntaxToken::Variable => "variable",
                XenomorphicSyntaxToken::VariableSpecial => "variable.special",
                XenomorphicSyntaxToken::Variant => "variant",
            }
        )
    }
}

impl XenomorphicSyntaxToken {
    pub fn find_best_token_color_match<'a>(
        &self,
        token_colors: &'a [VsCodeTokenColor],
    ) -> Option<&'a VsCodeTokenColor> {
        let mut ranked_matches = IndexMap::new();

        for (ix, token_color) in token_colors.iter().enumerate() {
            if token_color.settings.foreground.is_none() {
                continue;
            }

            let Some(rank) = self.rank_match(token_color) else {
                continue;
            };

            if rank > 0 {
                ranked_matches.insert(ix, rank);
            }
        }

        ranked_matches
            .into_iter()
            .max_by_key(|(_, rank)| *rank)
            .map(|(ix, _)| &token_colors[ix])
    }

    fn rank_match(&self, token_color: &VsCodeTokenColor) -> Option<u32> {
        let candidate_scopes = match token_color.scope.as_ref()? {
            VsCodeTokenScope::One(scope) => vec![scope],
            VsCodeTokenScope::Many(scopes) => scopes.iter().collect(),
        }
        .iter()
        .flat_map(|scope| scope.split(',').map(|s| s.trim()))
        .collect::<Vec<_>>();

        let scopes_to_match = self.to_vscode();
        let number_of_scopes_to_match = scopes_to_match.len();

        let mut matches = 0;

        for (ix, scope) in scopes_to_match.into_iter().enumerate() {
            // Assign each entry a weight that is inversely proportional to its
            // position in the list.
            //
            // Entries towards the front are weighted higher than those towards the end.
            let weight = (number_of_scopes_to_match - ix) as u32;

            if candidate_scopes.contains(&scope) {
                matches += 1 + weight;
            }
        }

        Some(matches)
    }

    pub fn fallbacks(&self) -> &[Self] {
        match self {
            XenomorphicSyntaxToken::CommentDoc => &[XenomorphicSyntaxToken::Comment],
            XenomorphicSyntaxToken::Number => &[XenomorphicSyntaxToken::Constant],
            XenomorphicSyntaxToken::VariableSpecial => &[XenomorphicSyntaxToken::Variable],
            XenomorphicSyntaxToken::PunctuationBracket
            | XenomorphicSyntaxToken::PunctuationDelimiter
            | XenomorphicSyntaxToken::PunctuationListMarker
            | XenomorphicSyntaxToken::PunctuationSpecial => &[XenomorphicSyntaxToken::Punctuation],
            XenomorphicSyntaxToken::StringEscape
            | XenomorphicSyntaxToken::StringRegex
            | XenomorphicSyntaxToken::StringSpecial
            | XenomorphicSyntaxToken::StringSpecialSymbol => &[XenomorphicSyntaxToken::String],
            _ => &[],
        }
    }

    fn to_vscode(self) -> Vec<&'static str> {
        match self {
            XenomorphicSyntaxToken::Attribute => vec!["entity.other.attribute-name"],
            XenomorphicSyntaxToken::Boolean => vec!["constant.language"],
            XenomorphicSyntaxToken::Comment => vec!["comment"],
            XenomorphicSyntaxToken::CommentDoc => vec!["comment.block.documentation"],
            XenomorphicSyntaxToken::Constant => vec!["constant", "constant.language", "constant.character"],
            XenomorphicSyntaxToken::Constructor => {
                vec![
                    "entity.name.tag",
                    "entity.name.function.definition.special.constructor",
                ]
            }
            XenomorphicSyntaxToken::Embedded => vec!["meta.embedded"],
            XenomorphicSyntaxToken::Emphasis => vec!["markup.italic"],
            XenomorphicSyntaxToken::EmphasisStrong => vec![
                "markup.bold",
                "markup.italic markup.bold",
                "markup.bold markup.italic",
            ],
            XenomorphicSyntaxToken::Enum => vec!["support.type.enum"],
            XenomorphicSyntaxToken::Function => vec![
                "entity.function",
                "entity.name.function",
                "variable.function",
            ],
            XenomorphicSyntaxToken::Hint => vec![],
            XenomorphicSyntaxToken::Keyword => vec![
                "keyword",
                "keyword.other.fn.rust",
                "keyword.control",
                "keyword.control.fun",
                "keyword.control.class",
                "punctuation.accessor",
                "entity.name.tag",
            ],
            XenomorphicSyntaxToken::Label => vec![
                "label",
                "entity.name",
                "entity.name.import",
                "entity.name.package",
            ],
            XenomorphicSyntaxToken::LinkText => vec!["markup.underline.link", "string.other.link"],
            XenomorphicSyntaxToken::LinkUri => vec!["markup.underline.link", "string.other.link"],
            XenomorphicSyntaxToken::Number => vec!["constant.numeric", "number"],
            XenomorphicSyntaxToken::Operator => vec!["operator", "keyword.operator"],
            XenomorphicSyntaxToken::Predictive => vec![],
            XenomorphicSyntaxToken::Preproc => vec![
                "preproc",
                "meta.preprocessor",
                "punctuation.definition.preprocessor",
            ],
            XenomorphicSyntaxToken::Primary => vec![],
            XenomorphicSyntaxToken::Property => vec![
                "variable.member",
                "support.type.property-name",
                "variable.object.property",
                "variable.other.field",
            ],
            XenomorphicSyntaxToken::Punctuation => vec![
                "punctuation",
                "punctuation.section",
                "punctuation.accessor",
                "punctuation.separator",
                "punctuation.definition.tag",
            ],
            XenomorphicSyntaxToken::PunctuationBracket => vec![
                "punctuation.bracket",
                "punctuation.definition.tag.begin",
                "punctuation.definition.tag.end",
            ],
            XenomorphicSyntaxToken::PunctuationDelimiter => vec![
                "punctuation.delimiter",
                "punctuation.separator",
                "punctuation.terminator",
            ],
            XenomorphicSyntaxToken::PunctuationListMarker => {
                vec!["markup.list punctuation.definition.list.begin"]
            }
            XenomorphicSyntaxToken::PunctuationSpecial => vec!["punctuation.special"],
            XenomorphicSyntaxToken::String => vec!["string"],
            XenomorphicSyntaxToken::StringEscape => {
                vec!["string.escape", "constant.character", "constant.other"]
            }
            XenomorphicSyntaxToken::StringRegex => vec!["string.regex"],
            XenomorphicSyntaxToken::StringSpecial => vec!["string.special", "constant.other.symbol"],
            XenomorphicSyntaxToken::StringSpecialSymbol => {
                vec!["string.special.symbol", "constant.other.symbol"]
            }
            XenomorphicSyntaxToken::Tag => vec!["tag", "entity.name.tag", "meta.tag.sgml"],
            XenomorphicSyntaxToken::TextLiteral => vec!["text.literal", "string"],
            XenomorphicSyntaxToken::Title => vec!["title", "entity.name"],
            XenomorphicSyntaxToken::Type => vec![
                "entity.name.type",
                "entity.name.type.primitive",
                "entity.name.type.numeric",
                "keyword.type",
                "support.type",
                "support.type.primitive",
                "support.class",
            ],
            XenomorphicSyntaxToken::Variable => vec![
                "variable",
                "variable.language",
                "variable.member",
                "variable.parameter",
                "variable.parameter.function-call",
            ],
            XenomorphicSyntaxToken::VariableSpecial => vec![
                "variable.special",
                "variable.member",
                "variable.annotation",
                "variable.language",
            ],
            XenomorphicSyntaxToken::Variant => vec!["variant"],
        }
    }
}
