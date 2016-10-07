#!/usr/bin/env perl

use Web::Simple qw/MyApplication/;


{
    package MyApplication;

    use Data::Printer;
    use Plack::Builder;
    use Plack::Request;
    use Log::Minimal;
    use Git::Repository;
    use Digest::HMAC_SHA1 qw/hmac_sha1_hex/;
    use JSON;
    use Email::Simple;
    use Email::Sender::Simple qw{ sendmail };
    use Email::Sender::Transport::SMTP::TLS;
    use Sereal::Decoder;
    use Data::Dumper;

    my $home = $ENV{HOME};
    my $config = {
        git                => '/usr/bin/git',
        secret             => 'StriverConniver',
        git_work_tree      => $home . '/repos/AlmostIsland',
        committer_email    => 'gbhat@pobox.com',
        committer_name     => 'Gurunandan Bhat',
        site_builder       => $home . '/repos/AICode/bin/aiweb.pl test',
        site_source_folder => 'source',
        email_creds        => $home . '/.ssh/email',
        email_from         => 'gbhat@pobox.com',
        email_to           => 'gbhat@pobox.com',
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
            $self->send_email($log);

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

        my $raw_body = $req->raw_body;
        $self->{_payload} = my $payload = decode_json( $raw_body );
        debugf('Payload was: ' . Dumper($payload));

        my $check   = 'sha1=' . hmac_sha1_hex($raw_body, $config->{secret});
        my $digest  = $req->headers->header('X-Hub-Signature');
        my $matched = $check eq $digest;

        debugf(sprintf('Validation: %s|%s Matched: %s', $check, $digest, ($matched ? 'Yes' : 'No')));

        return 1 if $matched;
    }


    sub build {

        my ($self, $repo) = @_;

        my $head_commit = $repo->run('rev-parse' => 'HEAD');
        my $remote_head_commit = $self->{_payload}{head_commit}{id};
        debugf(sprintf('Head Commit on Local|Remote is: %s|%s', $head_commit, $remote_head_commit));

        my $log = ['Head Commit on Local|Remote is: ' . $head_commit . '|' . $remote_head_commit];
        return $log if $head_commit eq $remote_head_commit;


        my @reset = $repo->run(reset => '--hard', 'origin/master');
        push @reset, ($repo->run(pull => 'origin',  'master'));
        debugf('Pull Status: ', Dumper \@reset);

        # Check if any source files have changed
        $self->{_build_required} = 0;

        my $src_folder = $config->{site_source_folder};
        BUILD_TEST_DONE:
        for my $commit ( @{ $self->{_payload}->{commits} } ) {
            for my $modified_file ( @{ $commit->{modified} } ) {
                next unless $modified_file =~ /^$src_folder\//;
                $self->{_build_required} = 1;
                last BUILD_TEST_DONE;
            }
        }

        my (@build, @refresh);
        do {
            my @action = `$config->{site_builder}`;
            @build = @action || ($?);

            debugf('Build Status: ' . Dumper(\@build));

            push @refresh, ($repo->run(add => '.'));
            push @refresh, ($repo->run(commit => '-m', sprintf('Automated Build %s', scalar localtime)));
            push @refresh, ($repo->run(push => 'origin', 'master'));

            debugf('Refresh Status: ', Dumper(\@refresh));

        } if $self->{_build_required};
        # push @refresh, ($repo->run(push => 'striverconniver', 'master'));
        push @$log, @reset, @build, @refresh;

        return $log;
    }

    sub send_email {

        my ($self, $log) = @_;

        my $action = sprintf('Automated %s Log', $self->{_build_required} ? 'Build and Pull' : 'Pull');
        my $email = Email::Simple->create(
            header => [
                From => $config->{email_from},
                To => $config->{email_to},
                ($config->{email_cc} ? (Cc => $config->{email_cc}) : ()),
                Subject => sprintf('%s: %s', $action, scalar localtime),
            ],
            body => "$action:\n" . Dumper($log),
        );

        my $creds;
        eval {
            open my $fh, '<', $config->{email_creds} or die "Cannot open creds file: $!";
            defined (my $enc_str = <$fh>) or die "Found no creds in file";
            chomp $enc_str;

            $creds = Sereal::Decoder->new({compress => 1})->decode($enc_str);
            die "Invalid creds structure - Failed to deseralize correctly"
                unless ref $creds eq 'HASH' && exists $creds->{username} && $creds->{password};

            1
        } or do {
            my $err = $@ || 'Zombie error';
            debugf("Error generating credentials: $err");
            die $err;
        };

        my $transport = Email::Sender::Transport::SMTP::TLS->new({
            host => 'email-smtp.us-east-1.amazonaws.com',
            port => 587,
            username => $creds->{username},
            password => $creds->{password},
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
                autodump => 1,
                formatter => sub {
                    my ($env, $time, $type, $message, $trace, $raw_message) = @_;
                    $raw_message =~ s/\\n/\n/g;
                    sprintf("%s [%s] [%s] %s at %s\n\n", $time, $type, $env->{REQUEST_URI}, $raw_message, $trace);
                };
            $app;
        };
    };
}

MyApplication->run_if_script;
