package Business::PayPal::IPN;

# $Id: IPN.pm,v 1.5 2003/01/23 02:54:27 sherzodr Exp $

use strict;
use warnings;
use LWP::UserAgent;
use Crypt::SSLeay;
use Carp 'croak';
use CGI qw/-oldstyle_urls/;

use vars qw($VERSION $GTW $AUTOLOAD $SUPPORTEDV $errstr);

($VERSION)  = '$Revision: 1.5 $' =~ m/Revision:\s*(\S+)/;
$SUPPORTEDV = '1.4';
$GTW        = 'https://www.paypal.com/cgi-bin/webscr';

# Preloaded methods go here.



sub AUTOLOAD {
  my $self = shift;

  unless ( ref($self) ) {
    croak "Method $AUTOLOAD is not a class method. You should call it on the object";
  }

  my ($field) = $AUTOLOAD =~ m/([^:]+)$/;
  if ( exists $self->{$field} ) {
    return $self->{$field};
  }

  croak "Attempt to call undefined method $AUTOLOAD";
}





sub DESTROY { }





sub new {
  my $class = shift;
  $class = ref($class) || $class;

  my $self = { @_ };

  bless $self, $class;

  $self->_init()          or return undef;
  $self->_validate_txn()  or return undef;

  unless ( $self->{notify_version} eq $SUPPORTEDV ) {
    croak "This library supports $SUPPORTEDV of PayPal IPN. Required support is $self->{notify_version}";
  }

  return $self;
}




sub cgi {
  my $self = shift;

  if ( defined $self->{_CGI_OBJ} ) {
    return $self->{_CGI_OBJ};
  }

  my $cgi = CGI->new();
  $self->{_CGI_OBJ} = $cgi;

  return $self->cgi();
}





sub _init {
  my $self = shift;

  my $cgi = $self->cgi() or croak "Couldn't create CGI object";

  my $i = 0;
  for ( $cgi->param() ) {
    $self->{$_} = $cgi->param($_);
    $i++;
  }

  unless ( $i > 3 ) {
    $errstr = "Insufficient content from the invoker: '" . $cgi->query_string() . "'";
    return undef;
  }

  return 1;
}


sub user_agent {
  my $self = shift;

  if ( defined $self->{_UA_OBJ} ) {
    return $self->{_UA_OBJ};
  }

  my $ua = LWP::UserAgent->new();
  $ua->agent("Business::PayPal::IPN/$VERSION");
  $self->{_UA_OBJ} = $ua;

  return $self->user_agent();
}





sub _validate_txn {
  my $self = shift;

  my $cgi = $self->cgi();

  $cgi->param(cmd => "_notify-validate");

  my $form_ref = {};
  for ( $cgi->param() ) {
    $form_ref->{$_} = $cgi->param($_) || "";
  }

  my $ua        = $self->user_agent();
  my $responce  = $ua->post($GTW, $form_ref);

  if ( $responce->is_error() ) {
    $errstr = "Couldn't connec to '$GTW': " . $responce->status_line();
    return undef;
  }

  if ( $responce->content() eq 'INVALID' ) {
    $errstr = "Couldn't validate the transaction. Responce: " . $responce->content();
    return undef;
  } elsif ( $responce->content() eq 'VERIFIED' ) {
    return 1;
  }

  # if we came this far, something is really wrong here:
  $errstr = "Vague responce: " . substr($responce->content(), 0, 255);
  return undef;
}





sub status {
  my $self = shift;

  return $self->{payment_status};
}


sub completed {
  my $self = shift;
  return ($self->{payment_status} eq 'Completed');
}


sub failed {
  my $self = shift;
  return ($self->{payment_status} eq 'Failed');
}

sub pending {
  my $self = shift;

  if ( $self->{payment_status} eq 'Pending' ) {
    return $self->{pending_reason};
  }
  return undef;
}

sub denied {
  my $self = shift;

  return ($self->{payment_status} eq 'Denied');
}


sub error {
  return $errstr;
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

$Revision: 1.5 $ of Business::PayPal::IPN supports version 1.4 of the API.
This was the latest version as of Wednesday, January 22, 2003. 
Supported version number is available in $Business::PayPal::IPN::SUPPORTEDV
global variable.

Note: If PayPal introduces new response variables, Business::PayPal::IPN
automatically supports those variables thanks to AUTOLOAD. For any further
updates, you can contact me.

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
    # no logging the same transaction twice. 

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

Crypt::SSLeay - to enable LWP perform https (SSL) requests

=back

=head1 METHODS

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

=head1 VARIABLES

Following global variables are available:

=over 4

=item *

$Business::PayPal::IPN::GTW - gateway url to PayPal's Web Script. Default
is "https://www.paypal.com/cgi-bin/webscr", which you may not want to 
change.

=item *

$Business::PayPal::IPN::SUPPORTEDV - supported version of PayPal's IPN API.
Default value is "1.4". You can modify it before creating ipn object (as long as you
know what you are doing. If not don't touch it!)

=item *

$Business::PayPal::IPN::VERSION - version of the library

=back

=head1 AUTHOR

Sherzod B. Ruzmetov E<lt>sherzodr@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Sherzod B. Ruzmetov.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 REVISION

$Revision: 1.5 $

=cut
