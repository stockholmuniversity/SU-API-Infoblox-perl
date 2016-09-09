package SU::API::Infoblox;

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request;
use URI::Escape;
use JSON;

sub new {
    my $class = shift;
    my $self = {
        hostname => shift,
        version  => shift,
    };

    $self->{url} = "https://$self->{hostname}/wapi/v$self->{version}";

    $self->{ua} = LWP::UserAgent->new;
    $self->{ua}->cookie_jar( {} );

    $self->{login_status} = "not logged in";

    bless $self, $class;
    return $self;
};

sub do_request {
    my ($self,$method,$object,$params) = @_;

    if($params) {
        $params = encode_params($params);
    }
    my $req = HTTP::Request->new($method => "$self->{url}/${object}");
    $req->content_type('application/x-www-form-urlencoded');
    $req->content($params);

    $self->{res} = $self->{ua}->request($req);

    if (!$self->{res}->is_success) {
        return undef;
    };
    my $json_result = decode_json($self->{res}->content);

    if ($json_result) {
        return $json_result;
    };
    return undef;
};

sub encode_params {
    my $params = $_[0];
    my @params_array;
    my @encoded_uri_array;

    if($params =~ /&/) {
        @params_array = split('&',$params);
    } else {
        @params_array = $params;
    };
    for(@params_array) {
        if($_ =~ /=/) {
            my ($argument,$value) = split("=",$_);
            push(@encoded_uri_array,join("=",uri_escape($argument),uri_escape($value)));
        } else {
            push(@encoded_uri_array,uri_escape($_));
        };
    };
    return join("&",@encoded_uri_array);
};

sub login {
    my ($self,$username,$password) = @_;

    $self->{username} = $username;
    $self->{password} = $password;

    $self->{ua}->credentials("$self->{hostname}:443", "InfoBlox ONE Platform", $self->{username}, $self->{password});

    my $req = HTTP::Request->new(GET => "$self->{url}/");
    my $res = $self->{ua}->request($req);

    if ($res->status_line eq "401 Authorization Required"){
        $self->{login_status} = "wrong username/password";
    } elsif ($self->{ua}->cookie_jar->{COOKIES}->{$self->{hostname}}) {
        $self->{login_status} = "login successful";
        $self->{logged_in} = 1;
    } else {
        $self->{login_status} = "unknown status line: " . $res->status_line;
    };

    return $self->{logged_in};
};

sub logout {
    my ($self) = @_;
    my $req = HTTP::Request->new(POST => "$self->{url}/logout");

    $self->{res} = $self->{ua}->request($req);

    if ($self->{res}->is_success) {
        $self->{logged_in} = undef;
    };
};

sub request_code {
    my ($self) = @_;
    return $self->{res}->code;
};

sub request_status_line {
    my ($self) = @_;
    return $self->{res}->status_line;
};

sub logged_in {
    my ($self) = @_;
    return $self->{logged_in};
};

sub login_status {
    my ($self) = @_;
    return $self->{login_status};
};

sub DESTROY {
    my ($self) = @_;
    if ($self->{ua} && $self->{logged_in}) {
        $self->logout();
    } elsif ($self->{logged_in}) {
        warn "Automatic logout failed";
    };
};

1;
