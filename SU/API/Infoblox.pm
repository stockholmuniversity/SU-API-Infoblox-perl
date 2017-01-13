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
    my ($self,$method,$object,$params,$data) = @_;

    my $request_url;
    my $content_type;
    my $content;

    if ($method eq "POST" or $method eq "PUT"){
        if ($data) {
           $data = encode_json($data);
        }

        $content_type = "application/json";
        $content = $data;

        # The 'request' object does not support URI arguments ($params) at all.
        if ($object eq "request"){
            $request_url = "$self->{url}/${object}";
        } else {
            # We want the POST and PUT calls to return JSON rather than a string.
            if (! $params) {
                $params = "_return_fields";
            } else {
                if ($params !~ /_return_fields/){
                    $params .= "&_return_fields";
                }
            }
            $params = encode_params($params);
            $request_url = "$self->{url}/${object}?$params";
        }
    } else {
        if ($params) {
            $params = encode_params($params);
        }
        $request_url = "$self->{url}/${object}";
        $content_type = "application/x-www-form-urlencoded";
        $content = $params;
    }

    my $req = HTTP::Request->new($method => $request_url);
    $req->content_type($content_type);
    $req->content($content);

    $self->{res} = $self->{ua}->request($req);

    if (!$self->{res}->is_success) {
        return undef;
    };

    # DELETE always returns the deleted ref as a string. We expect JSON.
    # Just return an anonymous hash directly, which mimics the format of the decoded JSON.
    if ($method eq "DELETE"){
        # the _ref string in the raw "content" contains " signs. These are not present
        # when we decode the JSON in the normal case.
        my $ref_string = $self->{res}->content;
        $ref_string =~ s/^"//;
        $ref_string =~ s/"$//;
        return {'_ref' => $ref_string};
    }

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
