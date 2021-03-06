function git_refresh_local_repos {
  git fetch -ap && git fetch --tags -p
}

function git_local_repos_is_clean {
  git_status=$(git status --untracked-files=no --porcelain)
  if [ -n "$git_status" ]
  then
    echo ""
    echo "Your local branch is not clean:"
    echo "$git_status"
    echo ""
    echo "Please commit and push first."
    echo ""
    return 1
  fi

  return 0  
}

function git_local_repos_is_sync {
  git_remote_tracking=$(git config branch.$(git name-rev --name-only HEAD).remote)
  if [ -n "$git_remote_tracking" ]
    then
    git_cherry=$(git cherry -v --abbrev)
    if [ -n "$git_cherry" ]
    then
      echo ""
      echo "There are pending commits:"
      echo "$git_cherry"
      echo ""
      echo "Please push them first ..."
      echo ""
      return 1
    fi
  fi

  return 0
}

function git_local_repos_is_sync_from_devel {
  if [ -n "$(git log ..origin/devel --oneline -n 1)" ]; then
    echo ""
    echo "You branch is out of sync with devel. Please rebase"
    echo ""
    echo "    * git rebase origin/devel"
    echo ""
    return 1
  fi
  return 0
}