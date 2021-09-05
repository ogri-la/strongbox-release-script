# -*- mode: ruby -*-
# vi: set ft=ruby :

VAGRANT_COMMAND = ARGV[0]
CUSTOM_SSH_KEY = File.expand_path("~/.ssh/id_rsa")

Vagrant.configure("2") do |config|
    config.vm.box = "bento/ubuntu-18.04"
    config.vm.box_check_update = false
    config.vm.provider "virtualbox" do |vb|
        vb.memory = "8096"
        vb.cpus = 8
    end

    if ['up', 'provision', 'reload'].include? VAGRANT_COMMAND
        config.vm.provision "shell" do |s|
            ssh_pem_key = File.read("#{CUSTOM_SSH_KEY}").strip
            ssh_pub_key = File.readlines("#{CUSTOM_SSH_KEY}.pub").first.strip
            github_token = File.read(".github-token").strip
            s.inline = <<-SHELL
                if ! grep --silent '#{ssh_pub_key}' /home/vagrant/.ssh/authorized_keys; then
                    echo #{ssh_pub_key} >> /home/vagrant/.ssh/authorized_keys
                fi
                echo '#{ssh_pem_key}' > /home/vagrant/.ssh/me.pem
                echo #{ssh_pub_key} > /home/vagrant/.ssh/me.pub
                chmod 0400 /home/vagrant/.ssh/me.*
                chown vagrant:vagrant /home/vagrant/.ssh/me.*
                echo '#{github_token}' > /home/vagrant/.github-token
            SHELL
        end

        config.vm.provision("shell",
            path: "bootstrap.sh", \
            keep_color: true,
            privileged: false)
    end

    if ["ssh", "ssh-config"].include? VAGRANT_COMMAND
        config.ssh.private_key_path = File.expand_path(CUSTOM_SSH_KEY)
    end
end
