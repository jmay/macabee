# Macabee

Extract contacts records from OSX Address Book as JSON. Apply updates to individual Address Book records via JSON.

## Installation

Add this line to your application's Gemfile:

    gem 'macabee'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install macabee

## Usage

Dump entire Address Book as JSON to standard output:

    $ macabee dump
    $ macabee contacts
    $ macabee groups

Dump out a single contact as JSON, where the `address-book-id` is the internal identifier, in the form "583BF34F-AD95-45FB-8521-05CB85C13079:ABPerson".

    $ macabee contact {address-book-id}
    $ macabee lookup [firstname] [lastname]

Compare a JSON input to the matching contact record in Address Book:

    $ macabee compare inputfile.json

Compare as above, and apply any changes to the Address Book record.

    $ macabee compare inputfile.json

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

https://jmay%40pobox.com@p08-contacts.icloud.com/16422197/carddavhome/card/

## TODO

* recognizing UUID changes - don't apply those changes, put the AB version back; when applying updates, refuse the entire batch if any UID values are different. Need a process for applying *only* UID corrections (no other attribute changes) back to the stored hash/treet representation.

  macabee compare xxx.json xref => emit only xref diffs
  macabee fixref xxx.json => apply xref diffs only back to the json, emit an updated json, stderr msg w summary

* redo `macabee` tool to use thor or other command-line framework
* refac: format conversion (currently only used for other.dob)
* promote fields from 'other' to top-level strings? (notes, dob) For sharing these individual values. Or allow sharing filters to use subkeys like 'other.notes'
* add specs: comparison, patching - need to mock AB, or create & delete a private AB for testing. Travis-CI does not support macruby (no OSX servers)
* comparisons for lists of contacts
* comparison for entire contact database (capture deletes)
* full code review to correct all the exception handling: return reasonable error classes, maybe don't always raise.
