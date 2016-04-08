Migrate Request Tracker Tickets to GitHub Issues
================================================

Uses the GitHub import issues API, currently still in preview.
`import_rt_to_github.pl` will list all tickets in a given queue on a given RT host, and import them as issues, including any/all Create, Comment, or Correspond child-transactions, including correct date/times and closing any tickets with the state 'resolved'.

I encourage anyone reading this to read and understand this script before proceeding.
Also: sorry. If you've ended up here, I feel your pain...

## It does NOT
* include all ticket transactions, links, merges, taken, steals etc.
* make any effort to translate RT users to GH users.


## Prerequisites
An OAuth token for the GitHub API.
The easiest way to do this is to generate a personal access token in your GitHub settings https://github.com/settings/tokens
However you create the OAuth token, the GitHub user you choose to do the loading must have `Admin` access to the target GitHub repo.


### Build and run in a Docker Container:

If you prefer not to make a mess of your local filesystem with perl muck (dependencies), then this can easily be run in a docker container.
```
docker build -t rt-migration .
docker run --rm -it --env-file env.list rt-migration
```
