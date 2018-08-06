use v6;

use PDF::COS::Tie :TiedEntry;

role PDF::COS::Tie::Hash
    does PDF::COS::Tie {

    #| resolve a heritable property by dereferencing /Parent entries
    sub find-prop($object, Str $key, :$seen is copy) {
	$object.AT-KEY($key, :check)
            // do with $object.AT-KEY('Parent', :check) {
                 $seen //= my %{Hash};
                 die "cyclical inheritance hierarchy"
                     if $seen{$object}++;
                 find-prop($_, $key, :$seen);
               }
    }

    method rw-accessor(Attribute $att, Str :$key!) is rw {
        Proxy.new(
            FETCH => {
                $att.tied.is-inherited
	            ?? find-prop(self, $key)
	            !! self.AT-KEY($key, :check);
            },
            STORE => -> $, \v {
                self.ASSIGN-KEY($key, v, :check);
            }
        );
    }

    method tie-init {
       my \class = self.WHAT;
       for class.^attributes.grep(TiedEntry) -> \att {
           my \key = att.tied.accessor-name;
           %.entries{key} //= att;
       }
    }

    method check {
        self.AT-KEY($_, :check)
            for (flat self.keys, self.entries.keys).unique;
        self.?cb-check();
        self
    }

    #| for hash lookups, typically $foo<bar>
    method AT-KEY($key, :$check) is rw {
        my $val := callsame;

        $val := $.deref(:$key, $val)
	    if $val ~~ Pair | List | Hash;

	my Attribute \att = %.entries{$key} // $.of-att;
        .tie($val, :$check) with att;
        $val;
    }

    #| handle hash assignments: $foo<bar> = 42; $foo{$baz} := $x;
    method ASSIGN-KEY($key, $val, :$check) {
	my $lval = $.lvalue($val);
	my Attribute \att = %.entries{$key} // $.of-att;

        .tie($lval, :$check) with att;
	nextwith($key, $lval )
    }

}
