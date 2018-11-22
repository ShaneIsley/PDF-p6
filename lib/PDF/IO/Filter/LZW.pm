use v6;
# code adapted from PDF::API2::Basic::PDF::Filter::LZWEncode
class PDF::IO::Filter::LZW {


    # Maintainer's Note: LZW is described in the PDF 32000 spec
    # in section 7.4.4
    use PDF::IO::Util;
    use PDF::IO::Filter::Predictors;
    use PDF::IO::Blob;

    sub predictor-class {
        state $predictor-class = PDF::IO::Util::libpdf-available()
            ?? (require ::('PDF::Native::Filter::Predictors'))
            !! PDF::IO::Filter::Predictors;
        $predictor-class
    }

    multi method encode($) {
	die "LZW encoding is not implemented.";
    }

    multi method decode(Str $input, |c) {
	$.decode($input.encode("latin-1"), |c);
    }
    multi method decode(Blob $in, :$Predictor, :$EarlyChange = 1, |c --> Blob) is default {

        my UInt \initial-code-len = 9;
        my UInt \clear-table = 256;
        my UInt \eod-marker = 257;
        my UInt \dict-size = 256;
        my uint16 $next-code = 258;
        my uint16 $code-len = initial-code-len;
        my @table = map {[$_,]}, (0 ..^ dict-size);
        my uint8 @data = $in.list;
        my uint8 @out;

        my uint16 $partial-code = 0;
        my uint16 $partial-bits = 0;

        while @data {
            my $code = self!read-dat(@data, $partial-code, $partial-bits, $code-len);
            last unless defined $code;

            unless $EarlyChange {
                if $next-code == (1 +< $code-len) and $code-len < 12 {
                    $code-len++;
                }
            }

            if $code == clear-table {
                $code-len = initial-code-len;
                $next-code = eod-marker + 1;
                next;
            }
            elsif $code == eod-marker {
                last;
            }
            elsif $code > eod-marker {
                @table[$next-code] = [@table[$code].list];
                @table[$next-code].push: @table[$code + 1][0];
            }
            else {
                @table[$next-code] = [@table[$code].list];
            }

            @out.append: @table[$next-code++];

            if $EarlyChange {
                if $next-code == (1 +< $code-len) and $code-len < 12 {
                    $code-len++;
                }
            }
        }

        my $out = buf8.new: @out;

        if $Predictor {
            $out = $.predictor-class.decode( $out, :$Predictor, |c );
        }

       PDF::IO::Blob.new: $out;
    }

    method !read-dat(@data, $partial-code is rw, $partial-bits is rw, $code-length) {

        while $partial-bits < $code-length {
            return Mu unless @data;
            $partial-code = ($partial-code +< 8) + @data.shift;
            $partial-bits += 8;
        }

        my $code = $partial-code +> ($partial-bits - $code-length);
        $partial-code +&= (1 +< ($partial-bits - $code-length)) - 1;
        $partial-bits -= $code-length;

        return $code;
    }
}
