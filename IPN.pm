package Business::PayPal::IPN;

# $Id: IPN.pm,v 1.11 2003/03/11 11:28:58 sherzodr Exp $

use strict;
use Carp 'croak';
use vars qw($VERSION $GTW $AUTOLOAD $SUPPORTEDV $errstr);

# Supported version of PayPal's IPN API
$SUPPORTEDV = '1.4';

# Gateway to PayPal's validation server as of this writing
$GTW        = 'https://www.paypal.com/cgi-bin/webscr';

# Revision of the library
$VERSION  = '1.9';

# Preloaded methods go here.

# Allows access to PayPal IPN's all the variables as method calls
sub AUTOLOAD {
  my $self = shift;

  unless ( ref($self) ) {
    croak "Method $AUTOLOAD is not a class method. You should call it on the object";
  }
  my ($field) = $AUTOLOAD =~ m/([^:]+)$/;
  if ( exists $self->{_PAYPAL_VARS}->{$field} ) {
    no strict 'refs';
    # Following line is not quite required to get it working,
    # but will speed-up subsequent accesses to the same method
    *{$AUTOLOAD} = sub { return $_[0]->{_PAYPAL_VARS}->{$field} };
    return $self->{_PAYPAL_VARS}->{$field};
  }
  croak "Attempt to call undefined method $AUTOLOAD";
}




# So that AUTOLOAD does not look for destructor. Expensive!
sub DESTROY { }





# constructor method. Initializes and returns Business::PayPal::IPN object
sub new {
  my $class = shift;
  $class = ref($class) || $class;

  my $self = { 
    _PAYPAL_VARS => {},
    query        => undef,
    ua           => undef,
    @_,
  };

  bless $self, $class;

  $self->_init()          or return undef;
  $self->_validate_txn()  or return undef;

  unless ( $self->{_PAYPAL_VARS}{notify_version} eq $SUPPORTEDV ) {
    croak "This library supports $SUPPORTEDV of PayPal IPN. Required support is $self->{_PAYPAL_VARS}{notify_version}";
  }
  return $self;
}





# initializes class object. Mainly, takes all query parameters presumably
# that came from PayPal, and assigns them as object attributes
sub _init {
  my $self = shift;

  my $cgi = $self->cgi() or croak "Couldn't create CGI object";
  map {
    $self->{_PAYPAL_VARS}->{$_} = $cgi->param($_)
  } $cgi->param();

  unless ( scalar( keys %{$self->{_PAYPAL_VARS}} > 3 ) ) {
    $errstr = "Insufficient content from the invoker:\n" . $self->dump();
    return undef;
  }
  return 1;
}




# validates the transaction by re-submitting it to the PayPal server
# and reading the response.
sub _validate_txn {
  my $self = shift;

  my $cgi = $self->cgi();
  my $ua  = $self->user_agent();

  # Adding a new field according to PayPal IPN manual
  $self->{_PAYPAL_VARS}->{cmd} = "_notify-validate";

  # making a POST request to the server with all the variables
  my $responce  = $ua->post( $GTW, $self->{_PAYPAL_VARS} );

  # caching the response object in case anyone needs it
  $self->{response} = $responce;
  
  if ( $responce->is_error() ) {
    $errstr = "Couldn't connect to '$GTW': " . $responce->status_line();
    return undef;
  }

  if ( $responce->content() eq 'INVALID' ) {
    $errstr = "Couldn't validate the transaction. Responce: " . $responce->content();
    return undef;
  } elsif ( $responce->content() eq 'VERIFIED' ) {
    return 1;
  }

  # if we came this far, something is really wrong here:
  $errstr = "Vague response: " . substr($responce->content(), 0, 255);
  return undef;
}




# returns all the PayPal's variables in the form of a hash
sub vars {
  my $self = shift;

  return %{ $self->{_PAYPAL_VARS} };
}







# returns standard CGI object
sub cgi {
  my $self = shift;

  if ( defined $self->{query} ) {
    return $self->{query};
  }

  require CGI;

  my $cgi = CGI->new();
  $self->{query} = $cgi;

  return $self->cgi();
}


# alias to cgi()
sub query {
  my $self = shift;

  return $self->cgi(@_);
}



# returns already created response object
sub response {
  my $self = shift;

  if ( defined $self->{response} ) {
    return $self->{response};
  }

  return undef;
}



# returns user agent object
sub user_agent {
  my $self = shift;

  if ( defined $self->{ua} ) {
    return $self->{ua};
  }

  require LWP::UserAgent;
  
  my $ua = LWP::UserAgent->new();
  $ua->agent( sprintf("Business::PayPal::IPN/%s (%s)", $VERSION, $ua->agent) );
  $self->{ua} = $ua;
  return $self->user_agent();
}






# The same as payment_status(), but shorter :-).
sub status {
  my $self = shift;
  return $self->{_PAYPAL_VARS}{payment_status};
}


# returns true if the payment status is completed
sub completed {
  my $self = shift;
  return ($self->status() eq 'Completed');
}


# returns true if the payment status is failed
sub failed {
  my $self = shift;
  return ($self->status() eq 'Failed');
}


# returns the reason for pending if the payment status
# is pending.
sub pending {
  my $self = shift;

  if ( $self->status() eq 'Pending' ) {
    return $self->{_PAYPAL_VARS}{pending_reason};
  }
  return undef;
}


# returns true if payment status is denied
sub denied {
  my $self = shift;

  return ($self->status() eq 'Denied');
}



# internally used to assign error messages to $errstr.
# Public interface should use it without any arguments
# to get the error message
sub error {
  my ($self, $msg) = @_;

  if ( defined $msg ) {
    $errstr = $msg;
  }

  return $errstr;
}





# for debugging purposes only. Returns the whole object
# as a perl data structure using Data::Dumper
sub dump {
  my ($self, $file, $indent) = @_;

  $indent ||= 1;

  require Data::Dumper;
  my $d = new Data::Dumper([$self], [ref($self)]);
  $d->Indent( $indent );

  if ( (defined $file) && (not -e $file) ) {
    open(FH, '>' . $file) or croak "Couldn't dump into $file: $!";    
    print FH $d->Dump();
    close(FH) or croak "Object couldn't be dumped into $file: $!";
  }

  return $d->Dump();
}




1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Business::PayPal::IPN - Perl extension that implements PayPal IPN v1.4

=head1 SYNOPSIS

  use Business::PayPal::IPN;

  my $ipn = new Business::PayPal::IPN() or die Business::PayPal::IPN->error();

  # if we came this far, you're guaranteed it went through,
  # and the transaction took place. But now you need to check
  # the status of the transaction, to see if it was completed
  # or still pending
  if ( $ipn->completed ) {
    # do something with it
  }


=head1 DESCRIPTION

Business::PayPal::IPN implements PayPal IPN version 1.4.
It validates transactions and gives you means to get notified
of payments to your PayPal account. If you don't already
know what PayPal IPN is this library may not be for you ;-).
Consult with respective manuals provided by PayPal.com.


=head2 WARNING

$Revision: 1.11 $ of Business::PayPal::IPN supports version 1.4 of the API.
This was the latest version as of Wednesday, January 22, 2003. 
Supported version number is available in $Business::PayPal::IPN::SUPPORTEDV
global variable.

Note: If PayPal introduces new response variables, Business::PayPal::IPN
automatically supports those variables thanks to AUTOLOAD. For any further
updates, you can contact me or send me a patch.

=head1 PAYPAL IPN OVERVIEW

As soon as you receive payment to your PayPal account, PayPal
posts the transaction details to your specified URL, which you either
configure in your PayPal preferences, or in your HTML forms' "notify_url"
hidden field.

When the payment details are received from, supposedly, PayPal server,
your application should check with the PayPal server to make sure
it is indeed a valid transaction, and that PayPal is aware of it.
This can be achieved by re-submitting the transaction details back to
https://www.paypal.com/cgi-bin/webscr and check the integrity of the data.

If the transaction is valid, PayPal will respond to you with a single string
"VERIFIED", and you can proceed safely. If the transaction is not valid,
you will receive "INVALID", and you can log the request for further investigation.

Business::PayPal::IPN is the library which encapsulates all the above
complexity into this compact form:

  my $ipn = new Business::PayPal::IPN() or die Business::PayPal::IPN->error();

  # if we come this far, we're guaranteed it was a valid transaction.
  if ( $ipn->completed() ) {
    # means the funds are already in our paypal account. But we should
    # still check against duplicates transaction ids to ensure we're
    # not logging the same transaction twice. 

  } elsif ( $ipn->pending() ) {
    # the payment was made to your account, but its status is still pending
    # $ipn->pending() also returns the reason why it is so.

  } elsif ( $ipn->denied() ) {
    # the payment denied

  } elsif ( $ipn->failed() ) {
    # the payment failed

  }

=head1 PREREQUISITES

=over 4

=item *

LWP - to make HTTP requests

=item *

Crypt::SSLeay - to enable LWP perform https (SSL) requests. If for any reason you
are not able to install Crypt::SSLeay, you will need to update 
$Business::PayPal::IPN::GTW to proper, non-ssl URL.

=back

=head1 METHODS

=over 4

=item *

C<new()> - constructor. Validates the transaction and returns IPN object
if everything was successful. Optionally you may pass it B<query> and B<ua>
options. B<query> denotes the CGI object to be used. B<ua> denotes the
user agent object. If B<ua> is missing, it will use LWP::UserAgent by default.

=item *

C<vars()> - returns all the returned PayPal variables and their respective
values in the form of a hash.

=item *

C<query()> - can also be accessed via C<cgi()> alias, returns respective
query object

=item *

C<response()> - returns HTTP::Response object, which is the content
returned while verifying transaction through PayPal. You normally never need
this method. In case you do for any reason, here it is.

=item *

C<user_agent()> - returns user agent object used by the library to verify the transaction.
Name of the agent is C<Business::PayPal::IPN/#.# (libwww-perl/#.##)>.

=back

Business::PayPal::IPN supports all the variables supported by PayPal IPN 
independent of its version. To access the value of any variable, 
use the corresponding method name. For example, if you want to get the 
first name of the user who made the payment ('first_name' variable):

  my $fname = $ipn->first_name();

To get the transaction id ('txn_id' variable):

  my $txn = $ipn->txn_id();

To get payment type ('payment_type' variable)

  $type = $ipn->payment_type();

and so on. For the list of all the available variables, consult IPN Manual
provided by PayPal Developer Network. You can find the link at the bottom
of http://www.paypal.com.

In addition to the above scheme, the library also provides convenience methods
such as:

=over 4

=item *

C<status()> - which is a shortcut to C<payment_status()>

=item *

C<failed()> - returns true if C<payment_status> is "Failed". 

=item *

C<completed()> - returns true if C<payment_status> is "Completed".

=item *

C<pending()> - returns true if C<payment_status> is "Pending". Return
value is also the string that explains why the payment is pending.

C<denied()> - returns true if C<payment_status> is "Denied".

=back

=head1 VARIABLES

Following global variables are available:

=over 4

=item *

$Business::PayPal::IPN::GTW - gateway url to PayPal's Web Script. Default
is "https://www.paypal.com/cgi-bin/webscr", which you may not want to 
change. But it comes handy while testing your application through a PayPal simulator.

=item *

$Business::PayPal::IPN::SUPPORTEDV - supported version of PayPal's IPN API.
Default value is "1.4". You can modify it before creating ipn object (as long as you
know what you are doing. If not don't touch it!)

=item *

$Business::PayPal::IPN::VERSION - version of the library

=back

=head1 AUTHOR

Sherzod B. Ruzmetov E<lt>sherzodr@cpan.orgE<gt>

=head1 CREDITS

Thanks to B<Brian Grossman> for his patches.

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Sherzod B. Ruzmetov.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

THIS LIBRARY IS PROVIDED WITH THE USEFULNESS IN MIND, BUT WITHOUT EVEN IMPLIED 
GUARANTEE OF MERCHANTABILITY NOR FITNESS FOR A PARTICULAR PURPOSE. USE IT AT YOUR OWN RISK.

=head1 REVISION

$Revision: 1.11 $

=cut
