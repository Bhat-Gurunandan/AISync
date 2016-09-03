#!/usr/bin/env perl

use Web::Simple qw/MyApplication/;


{
    package MyApplication;

    use Data::Printer;
    use Plack::Builder;
    use Log::Minimal;
    use Git::Repository;
    use Digest::HMAC_SHA1 qw/hmac_sha1_hex/;
    use JSON;
    use Email::Simple;
    use Email::Sender::Simple;
    use Email::Sender::Transport::SMTP;


    my $config = {
        git             => '/usr/bin/git',
        secret          => 'StriverConniver',
        git_work_tree   => '/home/nandan/repos/AlmostIsland',
        committer_email => 'gbhat@pobox.com',
        committer_name  => 'Gurunandan Bhat',
        site_builder    => '/home/nandan/repos/AICode/bin/aiweb.pl test',
        email_list      => [
            'gbhat@pobox.com',
            'rhymebawd@gmail.com',
        ],
    };

    sub dispatch_request {

        'POST + /sync' => sub {

            my ($self, $env) = @_;
            my $log;
            if ( $self->validate($env) ) {
                eval {
                    my $repo = Git::Repository->new(
                        work_tree => $config->{git_work_tree}, {
                            git => $config->{git},
                            env => {
                                GIT_COMMITTER_EMAIL => $config->{committer_email},
                                GIT_COMMITTER_NAME  => $config->{committer_name},
                            },
                        });
                    $log = $self->build($repo);
                    1;
                } or do {
                    $log = $@ || 'Zombie error';
                };
            }
            else {
                $log = "Cannot match GitHub secret"
            }

            debugf($log);
            send_email($log);

            return [
                200,
                ['Content-type' => 'text/plain'],
                [ 1 ],
            ];
        }
    }

    sub validate {

        my ($self, $env) = @_;
        my $req = Plack::Request->new($env);

        $self->{_payload} = $payload = decode_json( $req->raw_body );
        my $check   = 'sha1=' . hmac_sha1_hex($payload, 'StriverConniver');
        my $digest  = $req->headers->header('X-Hub-Signature');

        return 1 if ($check eq $digest);
    }

    sub build {

        my ($self, $repo) = @_;
        my $head_commit = $repo->run('rev-parse' => 'HEAD');

        my @log;
        if ( $head_commit ne $self->{_payload}{head_commit}{id} ) {

            @log = $repo->run(reset => '--hard', 'mycopy/master');
            push @log, ($repo->run(pull => 'mycopy',  'master'));

            my @action = `$config->{build}`;

            push @log, (@action || ($?));
            push @log, ($repo->run(add => '.'));
            push @log, ($repo->run(commit => '-m', sprintf('Automated Build %s', scalar localtime)));
            push @log, ($repo->run(push => 'mycopy', 'master'));
            push @log, ($repo->run(push => 'origin', 'master'));
        }

        return Dumper(\@log);
    }

    sub send_email {

        my $log = shift;
        $email = Email::Simple->create(
            header => [
                From => 'bhat.gurunandan@gmail.com',
                To => 'bhat.gurunandan@gmail.com',
                Cc => 'rhymebawd@gmail.com',
                Subject => sprintf('Automated Build: %s', scalar localtime),
            ],
            body => Dumper($log),
        );
        my $transport = Email::Sender::Transport::SMTP->new({
            host => 'aspmx.l.google.com',
            port => 25,
        });

        eval {
            sendmail($email, {transport => $transport});
            1;
        } or do {
            debugf($@ || 'Zombie Error');
        };
    }

    around to_psgi_app => sub {

        my ($orig, $self, $env) = @_;
        my $app = $self->$orig($env);

        builder {
            enable 'Plack::Middleware::Log::Minimal',
                loglevel => 'DEBUG',
                autodump => 1;
            $app;
        };
    };
}

MyApplication->run_if_script;
