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

    $ macabee

Dump out a single contact as JSON, where the `address-book-id` is the internal identifier, in the form "583BF34F-AD95-45FB-8521-05CB85C13079:ABPerson".

    $ macabee {address-book-id}

Compare a JSON input to the matching contact record in Address Book, and apply any changes to the Address Book record.

    $ macabee inputfile.json

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

https://jmay%40pobox.com@p08-contacts.icloud.com/16422197/carddavhome/card/

## TODO

* extract groups
