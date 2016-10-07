#!/usr/bin/env perl

use strict;
use warnings;

use Git::Repository;

my $home = $ENV{HOME};
my $config = {
    git             => '/usr/bin/git',
    secret          => 'StriverConniver',
    git_work_tree   => $home . '/repos/AlmostIsland',
    committer_email => 'gbhat@pobox.com',
    committer_name  => 'Gurunandan Bhat',
    site_builder    => $home . '/repos/AICode/bin/aiweb.pl test',
    email_creds     => $home . '/.ssh/email',
    email_from      => 'gbhat@pobox.com',
    email_to        => 'gbhat@pobox.com',
};

my $repo = Git::Repository->new(
    work_tree => $config->{git_work_tree}, {
        git => $config->{git},
        env => {
            GIT_COMMITTER_EMAIL => $config->{committer_email},
            GIT_COMMITTER_NAME  => $config->{committer_name},
        },
    });

my @reset = $repo->run(reset => '--hard', 'origin/master');
push @reset, ($repo->run(pull => 'origin',  'master'));

my @refresh;

push @refresh, ($repo->run(add => '.'));
push @refresh, ($repo->run(commit => '-m', sprintf('Automated Build %s', scalar localtime)));
push @refresh, ($repo->run(push => 'origin', 'master'));
push @refresh, ($repo->run(push => 'striverconniver', 'master'));

print "$_\n" foreach ( @reset, @refresh );

exit;
