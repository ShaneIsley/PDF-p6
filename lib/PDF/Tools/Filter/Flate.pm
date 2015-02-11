use v6;
# based on Perl 5's PDF::API::Core::PDF::Filter::ASCIIHexDecode

use PDF::Tools::Role::Predictors;

class PDF::Tools::Filter::Flate
    does PDF::Tools::Role::Predictors;

use Compress::Zlib;

# Maintainer's Note: Flate is described in the PDF 1.7 spec in section 3.3.3.
# See also http://www.libpng.org/pub/png/book/chapter09.html - PNG predictors

method encode(Str $input, *%params) {

    if $input ~~ m{(<-[\x0 .. \xFF]>)} {
        die 'illegal wide byte: U+' ~ $0.ord.base(16)
    }

    my $buf = $input.encode('latin-1');

    $buf = $.prediction( $buf, |%params )
        if %params<Predictor>:exists;

    compress( $buf ).decode('latin-1');
}

method decode(Str $input, Hash *%params --> Str) {

    my $buf = uncompress( $input.encode('latin-1') );

    $buf = $.post-prediction( $buf, |%params )
        if %params<Predictor>:exists;

    $buf.decode('latin-1');
}