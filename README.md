cluster_sshKey_setup.sh
    designed for test dev systems / home labs and NOT for productions
    run from a node/system that has access to all nodes you want to reach.
    enter subnet for nodes/systems
    it will use /etc/hosts to pull nodes to ssh into and setup keys and move to other nodes
    will prompt for username and pw (assumes same user and pw si used accross systems)
    at end of script it will run tests
