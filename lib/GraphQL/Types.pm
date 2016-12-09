use Hash::Ordered;

unit module GraphQL::Types;

class GraphQL::Type
{
    has Str $.name;
    has Str $.description is rw;

    method add-comment-description($/)
    {
        return unless $<Comment>;
        $!description = $<Comment>».made.join("\n");
    }

    method description-comment(Str $indent = '')
    {
        $.description.split(/\n/).map({ "$indent# $_\n" }).join('')
         if $.description
    }
}

role Deprecatable
{
    has Bool $.isDeprecated = False;
    has Str $.deprecationReason;

    method deprecate(Str $reason = "No longer supported.")
    {
	$!isDeprecated = True;
	$!deprecationReason = $reason;
    }

    method deprecate-str
    {
	' @deprecated(reason: "' ~ $!deprecationReason ~ '")'
	    if $!isDeprecated;
    }
}

class GraphQL::Scalar is GraphQL::Type
{
    has Str $.kind = 'SCALAR';

    method Str { self.description-comment ~ "scalar $.name\n" }
}

class GraphQL::String is GraphQL::Scalar
{
    has Str $.name = 'String';
}

class GraphQL::Int is GraphQL::Scalar
{
    has Str $.name = 'Int';
}

class GraphQL::Float is GraphQL::Scalar
{
    has Str $.name = 'Float';
}

class GraphQL::Boolean is GraphQL::Scalar
{
    has Str $.name = 'Boolean';
}

class GraphQL::ID is GraphQL::Scalar
{
    has Str $.name = 'ID';
}

class GraphQL::List is GraphQL::Type
{
    has Str $.kind = 'LIST';
    has GraphQL::Type $.ofType is rw;
    
    method name { '[' ~ $.ofType.name ~ ']' }
}

class GraphQL::Non-Null is GraphQL::Type
{
    has Str $.kind = 'NON_NULL';
    has GraphQL::Type $.ofType is rw;

    method name { $!ofType.name ~ '!' }
    method Str  { $!ofType.Str  ~ '!' }
}

class GraphQL::InputValue is GraphQL::Type
{
    has GraphQL::Type $.type is rw;
    has $.defaultValue;

    method Str
    {
        "$.name: $.type.name()" ~ (" = $.defaultValue"
                                       if $.defaultValue.defined)
    }
}

class GraphQL::Field is GraphQL::Type does Deprecatable
{
    has GraphQL::Type $.type is rw;
    has GraphQL::InputValue @.args is rw;
    has Sub $.resolver is rw;

    method Str(Str $indent = '')
    {
        self.description-comment($indent) ~
        "$indent$.name" ~
            ('(' ~ @!args.join(', ') ~ ')' if @!args)
        ~ ": $!type.name()" ~ self.deprecate-str
    }
}

role HasFields
{
    has GraphQL::Field @.fields;

    method field(Str $name)
    {
        @!fields.first: *.name eq $name;
    }

    method fields(Bool :$includeDeprecated)
    {
	@!fields.grep: {.name !~~ /^__/ and
                            ($includeDeprecated or not .isDeprecated) }
    }

    method fields-str (Str $indent = '')
    {
        self.fields(:includeDeprecated).map({.Str($indent)}).join("\n")
    }
}

class GraphQL::Interface is GraphQL::Type does HasFields
{
    has Str $.kind = 'INTERFACE';
    has GraphQL::Type @.possibleTypes;

    method Str
    {
        self.description-comment ~
        "interface $.name \{\n" ~ self.fields-str('  ') ~ "\n}\n"
    }
}

class GraphQL::Object is GraphQL::Type does HasFields
{
    has Str $.kind = 'OBJECT';
    has GraphQL::Interface @.interfaces is rw;
    has $.resolver is rw;

    method addfield($field) { push @!fields, $field }
    
    method fragment-applies(Str $fragmentType) returns Bool
    {
        return True if $fragmentType eq $.name;
        die "Check FragmentType in interfaces"; # need to add more checks
    }

    method Str
    {
        self.description-comment ~
        "type $.name " ~ 
            ('implements ' ~ (@!interfaces».name).join(', ') ~ ' '
                if @.interfaces)
        ~ "\{\n" ~ self.fields-str('  ') ~ "\n}\n"
    }
}

class GraphQL::Union is GraphQL::Type
{
    has $.kind = 'UNION';
    has GraphQL::Type @.possibleTypes;

    method Str
    {
        self.description-comment ~
        "union $.name = {(@!possibleTypes».name).join(' | ')}\n";
    }
}

class GraphQL::EnumValue is GraphQL::Scalar does Deprecatable
{
    
    method Str(Str $indent = '')
    { self.description-comment ~ "$indent$.name" ~ self.deprecate-str }
}

class GraphQL::Enum is GraphQL::Scalar
{
    has Str $.kind = 'ENUM';
    has GraphQL::EnumValue @.enumValues;

    method enumValues(Bool :$includeDeprecated)
    {
	@!enumValues.grep: {$includeDeprecated or not .isDeprecated}
    }
    
    method Str
    {
        self.description-comment ~
        "enum $.name \{\n" ~
            @!enumValues.map({ $_.Str('  ')}).join("\n") ~
        "\n}\n";
    }
}

class GraphQL::Directive is GraphQL::Type
{
    has GraphQL::EnumValue @.locations;
    has GraphQL::InputValue @.args;
}

#
# Default Types
#
our $GraphQLString  is export = GraphQL::String.new;
our $GraphQLFloat   is export = GraphQL::Float.new;
our $GraphQLInt     is export = GraphQL::Int.new;
our $GraphQLBoolean is export = GraphQL::Boolean.new;
our $GraphQLID      is export = GraphQL::ID.new;

our %defaultTypes is export =
    Int     => $GraphQLInt,
    Float   => $GraphQLFloat,
    String  => $GraphQLString,
    Boolean => $GraphQLBoolean,
    ID      => $GraphQLID;

class GraphQL::Operation
{
    has Str $.operation = 'query';
    has Str $.name;
    has %.vars;
    has %.directives;
    has @.selectionset;  # QueryField or Fragment

    method Str
    {
        ("$.operation $.name " if $.name) ~ "\{\n" ~
            @.selectionset.map({.Str('  ')}).join('') ~
        "}\n"
    }
}

class GraphQL::QueryField
{
    has Str $.alias;
    has Str $.name;
    has %.args;
    has GraphQL::Directive @.directives;
    has @.selectionset;

    method responseKey { $!alias // $!name }

    method Str(Str $indent = '')
    {
        $indent ~ ($!alias ~ ':=' if $!alias) ~ $!name
        ~
            ( '(' ~ %!args.keys.map({$_.Str ~ ':' ~ %!args{$_}.perl})
                               .join(', ') ~ ')' if %!args)
        ~
            ( " \{\n" ~ @!selectionset.map({.Str($indent ~ '  ')}).join('') ~
              $indent ~ '}' if @!selectionset)
        ~ "\n"
    }
}

class GraphQL::Fragment
{
    has Str $.name;
    has Str $.onType;
    has @.directives;
    has @.selectionset;

    method Str($indent = '')
    {
        "fragment $.name on $.onType" ~
            ( " \{\n" ~ @!selectionset.map({.Str($indent ~ '  ')}).join('') ~
              $indent ~ '}' if @!selectionset)
    }
}

class GraphQL::FragmentSpread
{
    has Str $.name;
    has @.directives;

    method Str($indent = '')
    {
        "$indent... $.name\n"
    }
}

class GraphQL::InlineFragment
{
    has Str $.onType;
    has @.directives;
    has @.selectionset;

    method Str($indent = '')
    {
        "$indent..."
            ~ (" on $.onType" if $.onType)
            ~ " \{\n" ~ @!selectionset.map({.Str($indent ~ '  ')}).join('')
            ~ $indent ~ "}\n"
    }
}

class GraphQL::Document
{
    has GraphQL::Operation %.operations;
    has GraphQL::Fragment  %.fragments;

    method GetOperation($operationName)
    {
        if $operationName.defined
        {
            return %!operations{$operationName}
                if %!operations{$operationName}.defined;
            die "Must provide an operation."
        }

        return %!operations.values.first if %!operations.elems == 1;

        die "Must provide operation name if query contains multiple operations."
    }

    method Str
    {
        (%.operations.values.map({.Str}).join("\n"),
         %.fragments.values.map({.Str}).join("\n")).join("\n")
        ~ "\n";
    }
}

class GraphQL::Schema
{
    has GraphQL::Type %!types = %defaultTypes;
    has Str $.query is rw = 'Query';
    has Str $.mutation is rw;

    method types { %!types.values }

    method addtype(GraphQL::Type $newtype)
    {
	%!types{$newtype.name} = $newtype
    }

    method type($typename) { %!types{$typename} }

    method queryType returns GraphQL::Object { %!types{$!query} }

    method mutationType returns GraphQL::Object { %!types{$!mutation} }

    method directives { die "No directives in schema yet" }

    method Str
    {
        my $str = '';

        for %!types.kv -> $typename, $type
        {
            next if %defaultTypes{$typename}.defined or $typename ~~ /^__/;
            $str ~= $type.Str ~ "\n";
        }

        $str ~= "schema \{\n";
	$str ~= "  query: $!query\n";
        $str ~= "  mutation: $!mutation\n" if $!mutation;
	$str ~= "}\n";
    }

    method resolvers(%resolvers)
    {
        for %resolvers.kv -> $type, $obj
        {
            die "Undefined object $type" unless %!types{$type};

            if ($obj ~~ Associative)
            {
                for $obj.kv -> $field, $resolver
                {
                    die "Undefined field $field for $type"
                        unless %!types{$type}.field($field);
                    
                    %!types{$type}.field($field).resolver = $resolver;
                }
            }
            else
            {
                %!types{$type}.resolver = $obj;
            }
        }
    }
}
