package AISync;

use Web::Simple;
use Data::Dumper;
use Plack::Request;
use JSON;

use AISync::Git;

sub dispatch_request {

    my ($self, $env) = @_;
    return (
        'POST + /sync' => sub {

            my ($self, $env) = @_;
            my $repo    = AISync::Git->new($env);

            return [
                200,
                ['Content-type' => 'text/plain'],
                [ $repo->build ],
            ];
        }
    );
}

1;
