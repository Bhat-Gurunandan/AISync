package AISync::Git;

use parent Git::Repository;

use Digest::HMAC_SHA1 qw{ hmac_sha1_hex };
use Data::Dumper;
use JSON;

my $payload;

sub new {

    my ($class, $env) = @_;

    my $req = Plack::Request->new($env);

    $payload = decode_json( $req->raw_body );
    my $digest  = $req->headers->header('X-Hub-Signature');
    my $check   = 'sha1=' . hmac_sha1_hex($payload, 'StriverConniver');

    return $class->SUPER::new(
        work_tree => '/home/nandan/repos/AlmostIsland', {
            git => '/usr/local/bin/git',
            env => {
                GIT_COMMITTER_EMAIL => 'gbhat@pobox.com',
                GIT_COMMITTER_NAME  => 'Gurunandan Bhat',
            },
        }
    );
}

sub build {

    my $self = shift;

    my $head_commit = $self->run('rev-parse' => 'HEAD');

    my @log;
    if ( $head_commit ne $payload->{head_commit}{id} ) {

        @log = $self->run(reset => '--hard', 'mycopy/master');
        push @log, ($self->run(pull => 'mycopy',  'master'));

        my @action = `/home/nandan/repos/AICode/bin/aiweb.pl test`;
        push @log, @action;

        push @log, ($self->run(add => '.'));
        push @log, ($self->run(commit => '-m', sprintf('Automated Build %s', scalar localtime)));
        push @log, ($self->run(push => 'mycopy', 'master'));
        push @log, ($self->run(push => 'origin', 'master'));
    }

    return Dumper(\@log);
}

1;
