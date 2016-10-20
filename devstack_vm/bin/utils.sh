#!/bin/bash

function cherry_pick(){
    commit=$1
    set +e
    git cherry-pick $commit

    if [ $? -ne 0 ]
    then
        echo "Ignoring failed git cherry-pick $commit"
        git checkout --force
    fi

    set -e
}

function git_revert(){
    commit=$1
    set +e
    git revert --no-edit $commit
 
    if [ $? -ne 0 ]
    then
        echo "Ignoring failed git revert $commit"
        git checkout --force
    fi

    set -e
}