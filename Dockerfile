FROM fedora:23
MAINTAINER "Richard Guest <quiffman@users.noreply.github.com>"


RUN dnf install -y yum-plugin-fastestmirror

RUN dnf install -y \
	tar patch \
	'perl(IO::Prompt::Tiny)' \
	'perl(Path::Tiny)' \
	'perl(RT::Client::REST::Ticket)' \
	'perl(Syntax::Keyword::Junction)' \
	'perl(autodie)' \
	'perl(Test::More)' \
	'perl(Module::Install)' \
	'perl(MIME::Base64)' \
	'perl(URI)' \
	'perl(URI::Escape)' \
	'perl(Moo)' \
	'perl(Types::Standard)' \
	'perl(JSON::MaybeXS)' \
	'perl(Cache::LRU)' \
	'perl(LWP::UserAgent)' \
	'perl(HTTP::Request)' \
	'perl(LWP::Protocol::https)' \
	&& \
	dnf clean all

WORKDIR /tmp
RUN curl -L -O https://github.com/fayland/perl-net-github/archive/master.tar.gz && \
	tar xvf master.tar.gz

WORKDIR /tmp/perl-net-github-master

ADD import_issues.patch ./

RUN patch -p1 < import_issues.patch

RUN	perl Makefile.PL && \
	make && \
	make test && \
	make install

ADD import_rt_to_github.pl /work/

ENTRYPOINT ["/work/import_rt_to_github.pl"]

#vim: set ts=4 sw=4 tw=0 :
