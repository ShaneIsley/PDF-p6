use v6;

use PDF::Object;
use PDF::Object::Stream;

# /Type /XRef - cross reference stream
# introduced with PDF 1.5
our class PDF::Object::Type::XRef
    is PDF::Object::Stream {

    use PDF::Storage::Util :resample;
    use PDF::Object::Tie;

    # See [PDF 1.7 Table 3.15]
    has Int $!Size is entry(:required);
    has Array $!Index is entry(:required);
    has Int $!Prev is entry(:required);
    has Array $!W is entry(:required);

    method first-obj-num is rw { self<Index>[0] }
    method next-obj-num is rw { self<Size> }

    method cb-setup-type( Hash $dict is rw ) {
        $dict<Type> = PDF::Object.compose( :name<XRef> );
    }

    method encode(Array $xref = $.decoded --> Str) {

        die 'mandatory /Index[0] entry is missing'
            unless $.first-obj-num.defined;

        die 'mandatory /Size entry is missing or zero'
            unless $.next-obj-num;

        self<W> //= [ 1, 2, 1 ];
        self<Size> //= 0;
        self<Index>[0] //= 0;
        self<Index>[1] //= $.Size;

        # /W resize to widest byte-widths, if needed
        for 0..2 -> $i {
            my Int $val = $xref.map({ .[$i] }).max;
            my Int $max-bytes;

            repeat {
                $max-bytes++;
                $val div= 256;
            } until $val == 0;

            $.W[$i] = $max-bytes
                if !$.W[$i] || $.W[$i] < $max-bytes;
        }

        my Str $str = resample( $xref, $.W, 8 ).chrs;
        nextwith( $str );
    }

    #= inverse of $.decode-to-stage2 . handily calculates and sets $.Size and $.Index
    method encode-from-stage2(Array $xref-index) {
        my @entries = $xref-index.list.sort: { $^a<obj-num> <=> $^b<obj-num> || $^a<gen-num> <=> $^b<gen-num> };

        my @xref;
        my $size = 0;
        my @index;
        my Array $encoded = [];

        for @entries -> $entry {
            my Bool $contigous = ?( $entry<obj-num> && $entry<obj-num> == $size );
            @index.push( $entry<obj-num>,  0 )
                unless $contigous;
            @index[*-1]++;
            my Array $item = do given $entry<type> {
                when 0|1 { [ $entry<type>, $entry<offset>, $entry<gen-num> ] }
                when 2   { [ $entry<type>, $entry<ref-obj-num>, $entry<index> ] }
                default  { die "unknown object type in XRef index: $_"}
            };
            $encoded.push( $item );
            $size = $entry<obj-num> + 1;
        }

        self<Size> = $size;
        self<Index> = @index;

        $.encode($encoded);
    }

    method decode($? --> Array) {
        my $chars = callsame;
        my $W = $.W
            // die "missing mandatory /XRef param: /W";

        my Array $xref-array = resample( $chars.encode('latin-1'), 8, $W );
        my $Size = $.Size
            // die "missing mandatory /XRef param: /Size";

        if $.Index {
            my $index = $.Index;
            my $n = [+] $index[1, 3 ... *];
            die "problem decoding /Type /XRef object. /Index specified $n objects, got {+$xref-array}"
                unless +$xref-array == $n;
        }

        $xref-array;
    }

    #= an extra decoding stage - build index entries from raw decoded data
    multi method decode-to-stage2($encoded = $.encoded) {

        my Int $i = 0;
        my Array $index = $.Index // [ 0, $.Size ];
        my Array $decoded-stage2 = [];

        my Array $decoded = $.decode( $encoded );

        for $index.list -> $obj-num is rw, $num-entries {

            for 1 .. $num-entries {
                my Array $idx = $decoded[$i++];
                my Int $type = $idx[0];
                given $type {
                    when 0|1 {
                        # free or inuse objects
                        my Int $offset = $idx[1];
                        my Int $gen-num = $idx[2];
                        $decoded-stage2.push: { :$type, :$obj-num, :$gen-num, :$offset };
                    }
                    when 2 {
                        # embedded objects
                        my Int $ref-obj-num = $idx[1];
                        my Int $index = $idx[2];
                        $decoded-stage2.push: { :$type, :$obj-num, :$ref-obj-num, :$index };
                    }
                    default {
                        die "XRef index object type outside range 0..2: $type"
                    }
                }
                $obj-num++;
            }
        }

        $decoded-stage2;
    }

}

