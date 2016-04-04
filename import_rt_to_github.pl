#!/usr/bin/env perl
use v5.10;
use strict;
use warnings;
use Carp;
use Data::Dump qw(dump);
use IO::Prompt::Tiny qw/prompt/;
use JSON::MaybeXS;
use Net::GitHub;
use Path::Tiny;
use RT::Client::REST::Ticket;
use RT::Client::REST;
use Syntax::Keyword::Junction qw/any/;

my $github_user       = prompt( "github user: ", $ENV{GH_USER});
my $github_token      = prompt( "github token: ", $ENV{GH_TOKEN});
my $github_repo_owner = prompt( "repo owner: ", $ENV{GH_REPO_OWNER});
my $github_repo       = prompt( "repo name: ", $ENV{GH_REPO});

my $rt_host = prompt( "RT Hostname: ", $ENV{RT_HOST});
my $rt_user = prompt( "RT ID: ", $ENV{RT_USER});
my $rt_password = prompt("RT password: ", $ENV{RT_PASSWORD});
my $rt_queue = prompt( "RT queue name: ", $ENV{RT_QUEUE});

my $gh = Net::GitHub->new( access_token => $github_token );
$gh->set_default_user_repo( $github_repo_owner, $github_repo );
# Extra Accept header, required to enable the issue importer API preview.
# Without it, the API responss with:
# `If you would like to help us test the Issue Importer API during its preview period, you must specify a custom media type in the 'Accept' header. Please see the docs for full details. at ./testing.pl line 24.`
$gh->ua->default_header('Accept', 'application/vnd.github.golden-comet-preview+json');
my $gh_repo = $gh->repos;

my $rt = RT::Client::REST->new( server => "https://$rt_host/" );
$rt->login(
    username => $rt_user,
    password => $rt_password
);

# see which tickets we already have on the github side
my @all_issues =
    $gh->issue->repos_issues( $github_repo_owner, $github_repo, { state => 'all' } );
while ($gh->issue->has_next_page) {
    push(@all_issues, $gh->issue->next_page);
}
my @gh_issues = 
    map { /\[\Q$rt_host\E #(\d+)\]/ }
    map { $_->{title} }
    @all_issues;

my @rt_tickets = $rt->search(
    type  => 'ticket',
    query => qq{
        Queue = '$rt_queue' 
        and
        ( Status = 'new' or Status = 'open' or Status = 'stalled' or Status = 'resolved')
    },
    orderby => 'id',
);


say "Found $#rt_tickets RT Tickets to consider copying.";

if ($#gh_issues > 0) {
    say "Found $#gh_issues GitHub issues that match the pattern for existing RT Tickets.";
}

my $dryrun = (prompt("Dry run, yes or no? (y/n)", "y") ne "n");

if (prompt("Continue, yes or no? (y/n)", "n") eq "n") {
    say "Exitting at user request.";
    exit 0;
}

for my $id (@rt_tickets) {

    if ( any(@gh_issues) eq $id ) {
        say "ticket #$id already on github";
        next;
    }

    # get the information from RT
    my $ticket = RT::Client::REST::Ticket->new(
        rt => $rt,
        id => $id,
    );
    $ticket->retrieve;


    # Start by grabbing the initial Ticket creation comment
    my $trans = $ticket->transactions(type => [qw(Create)])->get_iterator;

    my $ticket_created = $ticket->created_datetime;

    # Assume datetime sort order and use the first.
    # Also, use the time from the first create, as sometimes after RT merges there can be create
    # messages earlier than the ticket create time.
    my $create_body = "";
    my $create_id = 0;
    if (my $txn = $trans->()) {
        # This is the original create comment for this ticket (not from a merged ticket)
        $create_body = $txn->content;
        $create_body =~ s/^[-]{2,}[ ]*$/\n--/gms;
        #$create_body =~ s/^/> /gms;
        $create_id = $txn->id;

        my $created = $txn->created_datetime();
        if ($created < $ticket_created) {
            say "Found create transaction in RT #$id earlier than the ticket create time.";
            $ticket_created = $created;
        }
    }

    # Custom Fields
    my @cf_data;
    foreach my $cf_name ($ticket->cf) {
        if (my $cf = $ticket->cf($cf_name)) {
            push(@cf_data, "$cf_name | $cf");
        }
    }
    if (@cf_data) {
        $create_body =
        join("\n",
            "Custom Field | Value",
            "-------------|------",
            @cf_data
        ) . "\n\n" . $create_body;
    }

    # Gather all create, comment, and correspondance messages and turn them in to GH comments.
    $trans = $ticket->transactions(type => [qw(Create Comment Correspond)])->get_iterator;

    my @comments;
    while (my $txn = $trans->()) {
        next if ($txn->id == $create_id);
        my $created = $txn->created_datetime();
        my $content = $txn->content;
        next if $content eq '';
        $content =~ s/^[-]{2,}[ ]*$/\n--/gms;
        #$content =~ s/^/> /gms;
        push @comments, { 'body' => $content, 'created_at' => $created->iso8601() . 'Z' }
    }

    my $subject = $ticket->subject;

    my %import_issue = (
        'issue' => {
            'title' => "$subject [$rt_host #$id]",
            'body'  => "https://$rt_host/Ticket/Display.html?id=$id\n\n$create_body",
            'created_at' => $ticket_created->iso8601() . 'Z',
        },
        'comments' => [@comments],
    );
    if ($ticket->status eq 'resolved') {
        $import_issue{issue}{closed} = JSON->true;
        $import_issue{issue}{closed_at} = $ticket->resolved_datetime->iso8601() . 'Z';
    }

    if ($dryrun) {
        say "import_issues";
        say dump(%import_issue);
    }
    else {
        my %isu;
        eval {
            %isu = $gh_repo->import_issues(\%import_issue);
        } || say "Failed to import ticket #$id ($subject)\n" . dump(%import_issue);
        dump(%isu);
    }
    say "ticket #$id ($subject) copied to github";
}
# vim: set ts=4 sw=4 tw=0 et:
