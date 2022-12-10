@announce
@no-clobber
Feature: vagrant-zones
  In order to use Bhyve, LX or Native Illumos Zones
  As a Vagrant provider
  I want to use plugin for that

  Background:
    Given I write to "Vagrantfile" with:
      """
      Vagrant.configure(2) do |config|
        config.vm.box = 'vagrant-zones'
        config.vm.synced_folder '.', '/vagrant', type: 'rsync'
        config.ssh.private_key_path = '~/.ssh/id_rsa'
        config.vm.provision 'shell',
          inline: 'echo "it works" > /tmp/vagrant-zones-provision',
          privileged: false
      end
      """

  Scenario: creates server on up
    When I run `bundle exec vagrant up --provider=vagrant-zones`
    Then the exit status should be 0
    And the output should contain "Machine is booted and ready to use!"
    When I run `bundle exec vagrant status`
    Then the output should contain "active (vagrant-zones)"

  Scenario: starts created server on up
    When I run `bundle exec vagrant up --provider=vagrant-zones`
    And I run `bundle exec vagrant halt`
    And I run `bundle exec vagrant up --provider=vagrant-zones`
    Then the exit status should be 0
    And the output should contain "Machine is booted and ready to use!"
    When I run `bundle exec vagrant status`
    Then the output should contain "active (vagrant-zones)"

  Scenario: syncs folders
    When I run `bundle exec vagrant up --provider=vagrant-zones`
    And I run `bundle exec vagrant ssh -c "test -d /vagrant"`
    Then the exit status should be 0

  Scenario: provisions server
    When I run `bundle exec vagrant up --provider=vagrant-zones`
    And I run `bundle exec vagrant ssh -c "cat /tmp/vagrant-zones-provision"`
    Then the exit status should be 0
    And the output should contain "it works"

  Scenario: executes SSH to created server
    When I run `bundle exec vagrant up --provider=vagrant-zones`
    And I run `bundle exec vagrant ssh` interactively
    And I type "uname -a"
    And I close the stdin stream
    Then the output should contain "vagrant-zones.guest"

  Scenario: reboots server on reload
    When I run `bundle exec vagrant up --provider=vagrant-zones`
    And I run `bundle exec vagrant reload`
    Then the exit status should be 0
    And the output should contain "Machine is booted and ready to use!"
    When I run `bundle exec vagrant status`
    Then the output should contain "active (vagrant-zones)"

  Scenario: shutdowns server on halt
    When I run `bundle exec vagrant up --provider=vagrant-zones`
    And I run `bundle exec vagrant halt`
    Then the exit status should be 0
    And the output should contain "Machine is stopped."
    When I run `bundle exec vagrant status`
    Then the output should contain "off (vagrant-zones)"

  Scenario: removes server on destroy
    When I run `bundle exec vagrant up --provider=vagrant-zones`
    And I run `bundle exec vagrant destroy --force`
    Then the exit status should be 0
    And the output should contain "Machine is destroyed."
    When I run `bundle exec vagrant status`
    Then the output should contain "not created"
    
  
  Scenario: provides access to console
    When I run `bundle exec vagrant zone console zlogin`
