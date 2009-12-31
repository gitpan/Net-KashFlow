package Net::KashFlow;
use Carp qw/croak/;
use warnings;
use strict;
use Net::KashFlowAPI; # Autogenerated SOAP::Lite stubs

=head1 NAME

Net::KashFlow - Interact with KashFlow accounting web service

=head1 SYNOPSIS

    my $kf = Net::KashFlow->new(username => $u, password => $p);

    my $c = $kf->get_customer($cust_email);
    my $i = $kf->create_invoice({ 
        InvoiceNumber => time, CustomerID => $c->CustomerID 
    });

    $i->add_line({ Quantity => 1, Description => "Widgets", Rate => 100 })

    $i->pay({ PayAmount => 100 });

=head1 WARNING

This module is incomplete. It does not implement all of the KashFlow
API. Please find the github repository at
http://github.com/simoncozens/Net-KashFlow and send me pull requests for
your newly-implemented features. Thank you.

=head1 METHODS

=head2 new

Simple constructor - requires "username" and "password" named
parameters.

=cut

our $VERSION = '0.01';

sub new {
    my ($self, %args) = @_;
    for (qw/username password/) { 
        croak("You need to pass a '$_'") unless $args{$_};
    }
    bless { %args }, $self;
}

sub _c {
    my ($self, $method, @args) = @_;
    my ($result, $status, $explanation) = 
        KashFlowAPI->$method($self->{username}, $self->{password}, @args);
    if ($explanation) { croak($explanation) }
    return $result;
}

=head2 get_customer($id | $email)

Returns a Net::KashFlow::Customer object for the given customer. If the
parameter passed has an C<@> sign then this is treated as an email
address and the customer looked up email address; otherwise the
customer is looked up by customer code. If no customer is found in the
database, nothing is returned.

=cut

sub get_customer {
    my ($self, $thing, $by_id) = @_;
    my $method = "GetCustomer"; if ($thing =~ /@/) { $method.="ByEmail" }
    if ($by_id) { $method.="ByID" }
    my $customer;
    eval { $customer = $self->_c($method, $thing) };
    if ($@ =~ /no customer/) { return } die $@."\n" if $@;
    $customer = bless $customer, "Net::KashFlow::Customer";
    $customer->{kf} = $self;
    return $customer;
}

=head2 get_customer_by_id($internal_id)

Like C<get_customer>, but works on the internal ID of the customer.

=cut

sub get_customer_by_id { $_[0]->get_customer($_[1], 1) }

=head2 get_customers

Returns all customers

=cut

sub get_customers { 
    my $self = shift;
    return map { $_->{kf} = $self; bless $_, "Net::KashFlow::Customer" }
        @{$self->_c("GetCustomers")->{Customer}};
}

=head2 create_customer({ Name => "...", Address => "...", ... });

Inserts a new customer into the database, returning a
Net::KashFlow::Customer object.

=cut

sub create_customer {
    my ($self, $data) = @_;
    my $id = $self->_c("InsertCustomer", $data);
    return $self->get_customer_by_id($id);
}

=head2 get_invoice($your_id)

=head2 get_invoice_by_id($internal_id)

Returns a Net::KashFlow::Invoice object representing the invoice.

=cut

sub get_invoice {
    my ($self, $thing, $by_id) = @_;
    my $method = "GetInvoice"; if ($by_id) { $method.="ByID" }
    my $invoice;
    eval { $invoice = $self->_c($method, $thing) };
    if ($@ =~ /no invoice/) { return } die $@."\n" if $@;
    $invoice = bless $invoice, "Net::KashFlow::Invoice";
    $invoice->{kf} = $self;
    $invoice->{Lines} = bless $invoice->{Lines}, "InvoiceLineSet"; # Urgh
    return $invoice;
}
sub get_invoice_by_id { $_[0]->get_invoice($_[1], 1) }

=head2 create_invoice({ ... })

=cut

sub create_invoice {
    my ($self, $data) = @_;
    my $id = $self->_c("InsertInvoice", $data);
    return $self->get_invoice($id);
}   

package Net::KashFlow::Base;
use base 'Class::Accessor';

sub update {
    my $self = shift;
    my $copy = { %$self }; delete $copy->{kf};
    $self->{kf}->_c("Update".$self->_this(), $copy);
}

sub delete {
    my $self = shift;
    my $copy = { %$self }; delete $copy->{kf};
    $self->{kf}->_c("Delete".$self->_this(), $copy);
}

package Net::KashFlow::Customer;

=head1 Net::KashFlow::Customer

    my $c = $kf->get_customer($email);

    $c->Telephone("+44.500123456");
    $c->update;

    print $c->Address1(), $c->Address2();

Customer objects have accessors as specified by
C<http://accountingapi.com/manual_class_customer.asp> - these accessors
are not "live" in that changes to them are only sent to KashFlow on call
to the C<update> method.

This package also has a C<delete> method to remove the customer from the
database, and an C<invoices> method which returns all the
C<Net::KashFlow::Invoice> objects assigned to this customer.

=cut

use base 'Net::KashFlow::Base';
__PACKAGE__->mk_accessors(qw( 
 Contact Address2 ShowDiscount CheckBox1 EC OutsideEC PaymentTerms Discount
 Postcode CheckBox2 Website ExtraText1 Source Email Notes ExtraText2 Mobile
 Updated Telephone Code CustomerID Address1 Address4 Created Name Address3 Fax
));
sub _this { "Customer" }

sub invoices {
    my $self = shift;
    return map { $_->{kf} = $self->{kf}; 
        $_->{Lines} = bless $_->{Lines}, "InvoiceLineSet"; # Urgh
        bless $_, "Net::KashFlow::Invoice" 
    } @{$self->{kf}->_c("GetInvoicesForCustomer", $self->CustomerID)->{Invoice}};
}

package Net::KashFlow::Invoice;
use base 'Net::KashFlow::Base';
sub _this { "Invoice" }
__PACKAGE__->mk_accessors(qw/
DueDate NetAmount ProjectID Lines CustomerReference InvoiceDate InvoiceNumber
SuppressTotal CustomerID Customer CurrencyCode ReadableString ExchangeRate
 VATAmount AmountPaid Paid InvoiceDBID 
 /);

=head1 Net::KashFlow::Invoice

    my @i = $kf->get_customer($email)->invoices;
    for (@i) { $i->Paid(1); $i->update }

Similarly to Customer, fields found at
http://accountingapi.com/manual_class_invoice.asp

Also:

    $i->add_line({ Quantity => 1, Description => "Widgets", Rate => 100 });
    $i->pay({ PayAmount => 100 });

=cut

sub add_line {
    my ($self, $data) = @_;
    $self->{kf}->_c("InsertInvoiceLine", $self->InvoiceDBID, $data );
}

sub pay {
    my ($self, $data) = @_;
    $data->{PayInvoice} = $self->{InvoiceNumber};
    $self->{kf}->_c("InsertInvoicePayment", $data );
}

=head1 AUTHOR

Simon Cozens, C<< <simon at simon-cozens.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-net-kashflow at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-KashFlow>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

I am aware that this module is WOEFULLY INCOMPLETE and I'm looking
forward to receiving patches to add new functionality to it. Currently
it does what I want and I don't have much incentive to finish it. :/

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::KashFlow


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-KashFlow>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-KashFlow>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-KashFlow>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-KashFlow/>

=back


=head1 ACKNOWLEDGEMENTS

Thanks to the UK Free Software Network (http://www.ukfsn.org/) for their
support of this module's development. For free-software-friendly hosting
and other Internet services, try UKFSN.

=head1 COPYRIGHT & LICENSE

Copyright 2009 Simon Cozens.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1; # End of Net::KashFlow