module ParseUnparseWKTCRS
    export GrammarSymbolKinds, TokenUtil, ParserIdents
    module GrammarSymbolKinds
        export GrammarSymbolKind, grammar_symbol_error_kinds
        using ParseUnparse.KindConstruction
        struct GrammarSymbolKind
            opaque::UInt8
            const global kind_to_name = Dict{GrammarSymbolKind, String}()
            const global name_to_kind = Dict{String, GrammarSymbolKind}()
            next_opaque::UInt8 = 0x0
            function constructor_helper()
                opaque = next_opaque
                next_opaque = Base.checked_add(opaque, oftype(opaque, 1))
                new(opaque)
            end
            function GrammarSymbolKind(name::String)
                construct_kind!(constructor_helper, kind_to_name, name_to_kind, name)
            end
        end
        function Base.show(io::IO, kind::GrammarSymbolKind)
            if !haskey(kind_to_name, kind)
                throw(ArgumentError("unrecognized grammar symbol kind"))
            end
            print(io, kind_to_name[kind])
        end
        # terminal symbols
        const number = GrammarSymbolKind("number")
        const keyword = GrammarSymbolKind("keyword")
        const string = GrammarSymbolKind("string")  # called something like "quoted text" in the spec
        const list_delimiter_left = GrammarSymbolKind("list_delimiter_left")
        const list_delimiter_right = GrammarSymbolKind("list_delimiter_right")
        const list_element_separator = GrammarSymbolKind("list_element_separator")
        # nonterminal symbols
        const optional_incomplete_list = GrammarSymbolKind("optional_incomplete_list")
        const list = GrammarSymbolKind("list")
        const optional_delimited_list = GrammarSymbolKind("optional_delimited_list")
        const keyword_with_optional_delimited_list = GrammarSymbolKind("keyword_with_optional_delimited_list")
        const value = GrammarSymbolKind("value")
        # not part of the grammar, error in lexing/tokenization
        const lexing_error_unknown = GrammarSymbolKind("lexing_error_unknown")
        const lexing_error_expected_string = GrammarSymbolKind("lexing_error_expected_string")
        const lexing_error_expected_number = GrammarSymbolKind("lexing_error_expected_number")
        const grammar_symbol_error_kinds = (
            lexing_error_unknown,
            lexing_error_expected_string,
            lexing_error_expected_number,
        )
    end
    module TokenIterators
        export TokenIterator, encode_string, decode_string
        using ParseUnparse.LexingUtil, ..GrammarSymbolKinds
        struct TokenIterator{ListDelimiters, T}
            character_iterator::T
            function TokenIterator{ListDelimiters}(character_iterator) where {ListDelimiters}
                new{ListDelimiters::Tuple{Char, Char}, typeof(character_iterator)}(character_iterator)
            end
        end
        function token_iterator_list_delimiters(::TokenIterator{ListDelimiters}) where {ListDelimiters}
            ListDelimiters::Tuple{Char, Char}
        end
        function Base.IteratorSize(::Type{<:TokenIterator})
            Base.SizeUnknown()
        end
        const significant_characters = (;
            general = (;
                whitespace = ('\t', '\n', '\r', ' '),
                list_element_separator = (',',),
                double_quote = ('"',),
                decimal_digit = ('0' : '9'),
                alpha_lower = ('a' : 'z'),
                alpha_upper = ('A' : 'Z'),
                underscore = ('_',),
            ),
            number = (;
                e = ('E',),
                decimal_separator = ('.',),
                sign = ('-', '+'),
            ),
        )
        function character_does_not_need_escaping(c::AbstractChar)
            c ∉ significant_characters.general.double_quote
        end
        function character_is_keyword(c::AbstractChar)
            (c ∈ significant_characters.general.underscore) ||
            (c ∈ significant_characters.general.alpha_lower) ||
            (c ∈ significant_characters.general.alpha_upper)
        end
        function character_is_number_start(c::AbstractChar)
            (c ∈ significant_characters.number.decimal_separator) ||
            (c ∈ significant_characters.number.sign) ||
            (c ∈ significant_characters.general.decimal_digit)
        end
        function lex_keyword!(lexer_state)
            once = false
            while true
                if (
                    isempty(lexer_state_peek!(lexer_state)) ||
                    !character_is_keyword(only(lexer_state_peek!(lexer_state)))
                )
                    break
                end
                once = true
                lexer_state_consume!(lexer_state)
            end
            if !once
                throw(ArgumentError("unexpected error, empty keyword"))
            end
            GrammarSymbolKinds.keyword
        end
        function lex_string!(lexer_state)
            # Minimized DFA:
            #
            # * three states
            #
            # * 'c' stands for any Unicode character except for '"'
            #
            # * https://cyberzhg.github.io/toolbox/min_dfa?regex=IigoY3woIiIpKSopIg==
            ret = GrammarSymbolKinds.string
            # state 1
            let oc = lexer_state_consume!(lexer_state)
                if isempty(oc)
                    @goto string_error
                end
                if only(oc) ∉ significant_characters.general.double_quote
                    @goto string_error
                end
            end
            @label state_2
            let oc = lexer_state_consume!(lexer_state)
                if isempty(oc)
                    @goto string_error
                end
                if character_does_not_need_escaping(only(oc))
                    @goto state_2
                end
            end
            # state 3, accepting state
            let oc = lexer_state_peek!(lexer_state)
                if isempty(oc)
                    @goto string_done
                end
                if !character_does_not_need_escaping(only(oc))
                    lexer_state_consume!(lexer_state)
                    @goto state_2
                end
            end
            @goto string_done
            @label string_error
            ret = GrammarSymbolKinds.lexing_error_expected_string
            @label string_done
            ret
        end
        function lex_number!(lexer_state)
            # Minimized DFA:
            #
            # * eight states
            #
            # * 'a' stands for any digit between '0' and '9'
            #
            # * 's' stands for either '+' or '-'
            #
            # * 'e' stands for 'E'
            #
            # * https://cyberzhg.github.io/toolbox/min_dfa?regex=KHM/KSgoKGErKSgoLigoYSspPykpPykpfCguKGErKSkpKChlKHM/KShhKykpPyk=
            ret = GrammarSymbolKinds.number
            # state 1
            let oc = lexer_state_consume!(lexer_state)
                if isempty(oc)
                    @goto number_error
                end
                c = only(oc)
                if c ∈ significant_characters.general.decimal_digit
                    @goto state_3
                end
                if c ∈ significant_characters.number.decimal_separator
                    @goto state_2
                end
                if c ∉ significant_characters.number.sign
                    @goto number_error
                end
            end
            # state 4
            let oc = lexer_state_consume!(lexer_state)
                if isempty(oc)
                    @goto number_error
                end
                c = only(oc)
                if c ∈ significant_characters.general.decimal_digit
                    @goto state_3
                end
                if c ∉ significant_characters.number.decimal_separator
                    @goto number_error
                end
            end
            @label state_2
            let oc = lexer_state_consume!(lexer_state)
                if isempty(oc)
                    @goto number_error
                end
                if only(oc) ∉ significant_characters.general.decimal_digit
                    @goto number_error
                end
            end
            @label state_5  # accepting state
            let oc = lexer_state_peek!(lexer_state)
                if isempty(oc)
                    @goto number_done
                end
                c = only(oc)
                c_is_decimal_digit = c ∈ significant_characters.general.decimal_digit
                if c_is_decimal_digit || (c ∈ significant_characters.number.e)
                    lexer_state_consume!(lexer_state)
                    if c_is_decimal_digit
                        @goto state_5
                    end
                    @goto state_6
                end
            end
            @goto number_done
            @label state_6
            let oc = lexer_state_consume!(lexer_state)
                if isempty(oc)
                    @goto number_error
                end
                c = only(oc)
                if c ∈ significant_characters.general.decimal_digit
                    @goto state_7
                end
                if c ∉ significant_characters.number.sign
                    @goto number_error
                end
            end
            @label state_8
            let oc = lexer_state_consume!(lexer_state)
                if isempty(oc)
                    @goto number_error
                end
                if only(oc) ∉ significant_characters.general.decimal_digit
                    @goto number_error
                end
            end
            @label state_7  # accepting state
            let oc = lexer_state_peek!(lexer_state)
                if isempty(oc)
                    @goto number_done
                end
                if only(oc) ∈ significant_characters.general.decimal_digit
                    lexer_state_consume!(lexer_state)
                    @goto state_7
                end
            end
            @goto number_done
            @label state_3  # accepting state
            let oc = lexer_state_peek!(lexer_state)
                if isempty(oc)
                    @goto number_done
                end
                c = only(oc)
                c_is_decimal_digit = c ∈ significant_characters.general.decimal_digit
                c_is_decimal_separator = c ∈ significant_characters.number.decimal_separator
                if c_is_decimal_digit || c_is_decimal_separator || (c ∈ significant_characters.number.e)
                    lexer_state_consume!(lexer_state)
                    if c_is_decimal_digit
                        @goto state_3
                    end
                    if c_is_decimal_separator
                        @goto state_5
                    end
                    @goto state_6
                end
            end
            @goto number_done
            @label number_error
            ret = GrammarSymbolKinds.lexing_error_expected_number
            @label number_done
            ret
        end
        function Base.iterate(
            token_iterator::TokenIterator,
            token_iterator_state::TokenIteratorState{Nothing, Char} = token_iterator_state_init(Char, nothing),
        )
            if token_iterator_state.is_done
                nothing
            else
                let symbol_kind
                    lexer_state = let o = lexer_state_new(token_iterator_state.opaque, token_iterator_state.extra, token_iterator.character_iterator)
                        if o === ()
                            return nothing
                        end
                        only(o)
                    end
                    initial_consumed_character_count = lexer_state_get_consumed_character_count(lexer_state)
                    have_token = false
                    while !isempty(lexer_state_peek!(lexer_state))
                        if only(lexer_state_peek!(lexer_state)) ∈ significant_characters.general.whitespace
                            lexer_state_consume!(lexer_state)
                        else
                            have_token = true
                            symbol_kind = if character_is_keyword(only(lexer_state_peek!(lexer_state)))
                                lex_keyword!(lexer_state)
                            elseif only(lexer_state_peek!(lexer_state)) ∈ significant_characters.general.double_quote
                                lex_string!(lexer_state)
                            elseif character_is_number_start(only(lexer_state_peek!(lexer_state)))
                                lex_number!(lexer_state)
                            else
                                let c = only(lexer_state_consume!(lexer_state))
                                    (list_delimiter_left, list_delimiter_right) = token_iterator_list_delimiters(token_iterator)
                                    if c ∈ significant_characters.general.list_element_separator
                                        GrammarSymbolKinds.list_element_separator
                                    elseif c ∈ list_delimiter_left
                                        GrammarSymbolKinds.list_delimiter_left
                                    elseif c ∈ list_delimiter_right
                                        GrammarSymbolKinds.list_delimiter_right
                                    else
                                        GrammarSymbolKinds.lexing_error_unknown
                                    end
                                end
                            end::GrammarSymbolKind
                            while true  # optional trailing whitespace
                                if (
                                    isempty(lexer_state_peek!(lexer_state)) ||
                                    (only(lexer_state_peek!(lexer_state)) ∉ significant_characters.general.whitespace)
                                )
                                    break
                                end
                                lexer_state_consume!(lexer_state)
                            end
                            break
                        end
                    end
                    if have_token
                        let consumed_character_count = lexer_state_get_consumed_character_count(lexer_state)
                            (; opaque, token_source) = lexer_state_destroy!(lexer_state)
                            source_range_of_token = (initial_consumed_character_count + true):consumed_character_count
                            token = ((source_range_of_token, String(token_source)), symbol_kind)
                            state = (; is_done = symbol_kind ∈ grammar_symbol_error_kinds, extra = token_iterator_state.extra, opaque)
                            (token, state)
                        end
                    else
                        nothing
                    end
                end
            end
        end
        function encode_string_single_char(out::IO, decoded::AbstractChar)
            q = only(significant_characters.general.double_quote)
            print(out, decoded)
            if decoded == q
                print(out, decoded)
            end
        end
        function encode_string_no_quotes(out::IO, decoded)
            foreach(Base.Fix1(encode_string_single_char, out), decoded)
        end
        """
            encode_string(out::IO, decoded)::Nothing

        Encode the `decoded` iterator as a WKT-CRS string, outputting to `out`.
        """
        function encode_string(out::IO, decoded)
            q = only(significant_characters.general.double_quote)
            print(out, q)
            encode_string_no_quotes(out, decoded)
            print(out, q)
            nothing
        end
        """
            decode_string(out::IO, encoded)::Bool

        Decode the `encoded` iterator, interpreted as a WKT-CRS string, outputting to `out`.

        Return `true` if and only if no error was encountered.
        """
        function decode_string(out::IO, encoded)
            lexer_state = let ols = lexer_state_simple_new(encoded)
                if ols === ()
                    return false
                end
                only(ols)
            end
            dquot = significant_characters.general.double_quote
            # This is a finite-state machine just like in `lex_string!`, but starting
            # with an extra state to skip initial white space and ending with an extra
            # state to check there's nothing except for white space at the end.
            while true
                oc = lexer_state_consume!(lexer_state)
                if isempty(oc)
                    return false
                end
                c = only(oc)
                if c ∈ dquot
                    break
                end
                if c ∉ significant_characters.general.whitespace
                    return false
                end
            end
            # state 1 is merged into the above
            @label state_2
            let oc = lexer_state_consume!(lexer_state)
                if isempty(oc)
                    return false
                end
                c = only(oc)
                if character_does_not_need_escaping(c)
                    print(out, c)
                    @goto state_2
                end
            end
            # state 3, accepting state
            let oc = lexer_state_peek!(lexer_state)
                if isempty(oc)
                    return true
                end
                c = only(oc)
                if !character_does_not_need_escaping(c)
                    print(out, c)
                    lexer_state_consume!(lexer_state)
                    @goto state_2
                end
            end
            # trailing whitespace
            while true
                oc = lexer_state_consume!(lexer_state)
                if isempty(oc)
                    break
                end
                if only(oc) ∉ significant_characters.general.whitespace
                    return false
                end
            end
            true
        end
    end
    module TokenUtil
        export encode_string, decode_string
        using ..TokenIterators
    end
    module ParserIdents
        export ParserIdent
        using ParseUnparse.ContextFreeGrammarUtil, ParseUnparse.SymbolGraphs, ParseUnparse.AbstractParserIdents, ..GrammarSymbolKinds, ..TokenIterators
        struct ParserIdent{Debug <: Nothing, ListDelimiters} <: AbstractParserIdent
            function ParserIdent{Debug, ListDelimiters}() where {Debug <: Nothing, ListDelimiters}
                new{Debug, ListDelimiters::Tuple{Char, Char}}()
            end
        end
        function ParserIdent{Debug}() where {Debug <: Nothing}
            ParserIdent{Debug, ('[', ']')}()
        end
        function ParserIdent()
            ParserIdent{Nothing}()
        end
        function get_debug(::ParserIdent{Debug}) where {Debug <: Nothing}
            Debug
        end
        function get_list_delimiters(::ParserIdent{<:Nothing, ListDelimiters}) where {ListDelimiters}
            ListDelimiters::Tuple{Char, Char}
        end
        function AbstractParserIdents.get_lexer(id::ParserIdent)
            TokenIterator{get_list_delimiters(id)}
        end
        function AbstractParserIdents.get_token_grammar(::ParserIdent)
            start_symbol = GrammarSymbolKinds.value
            grammar = Dict{GrammarSymbolKind, Set{Vector{GrammarSymbolKind}}}(
                (GrammarSymbolKinds.value => Set(([GrammarSymbolKinds.number], [GrammarSymbolKinds.string], [GrammarSymbolKinds.keyword_with_optional_delimited_list]))),
                (GrammarSymbolKinds.keyword_with_optional_delimited_list => Set(([GrammarSymbolKinds.keyword, GrammarSymbolKinds.optional_delimited_list],))),
                (GrammarSymbolKinds.optional_delimited_list => Set(([], [GrammarSymbolKinds.list_delimiter_left, GrammarSymbolKinds.list, GrammarSymbolKinds.list_delimiter_right],))),
                (GrammarSymbolKinds.list => Set(([], [GrammarSymbolKinds.value, GrammarSymbolKinds.optional_incomplete_list]))),
                (GrammarSymbolKinds.optional_incomplete_list => Set(([], [GrammarSymbolKinds.list_element_separator, GrammarSymbolKinds.value, GrammarSymbolKinds.optional_incomplete_list]))),
            )
            (start_symbol, grammar)
        end
        function AbstractParserIdents.get_token_parser(id::ParserIdent)
            (start_symbol, grammar) = get_token_grammar(id)
            tables = make_parsing_table_strong_ll_1(grammar, start_symbol)
            Debug = get_debug(id)
            StrongLL1TableDrivenParser{Debug, Tuple{UnitRange{Int64}, String}}(start_symbol, tables...)
        end
    end
end
