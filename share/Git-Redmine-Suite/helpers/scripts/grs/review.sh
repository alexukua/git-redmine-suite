function review_start {
	TASK=$1
	if [ -z "$TASK" ]; then
		echo "Missing TASK_NUMBER : "
		echo ""
		HELP=1 exec $0
	fi

	CURRENT_TASK=$(git config redmine.review.current)

	if [ -n "$CURRENT_TASK" ]
	then
    	cat<<__EOF__
This review is already in progress.
You have to abort the review before and start it again.

    git redmine review abort
    git redmine review start $TASK

__EOF__
    	exit 1
	fi

	PR=$(redmine-get-task-pr --task_id=$TASK --cf_names=GIT_PR)
	if [ -z "$PR" ]
	    then
	    echo "No PR found in the task $TASK"
	    echo "Fill the GIT_PR field if you have one."
	    echo ""
	    exit 1
	fi

	echo "Starting the review : "
	if ! redmine-get-task-info --task_id=$TASK --with-extended-status; then
		exit 1
	fi
	if [ -z "$REDMINE_CHAIN" ]; then
		if ! ask_question --question="Do you really want to start this task ?"; then
			exit 1
		fi
	fi
	
	task=$TASK \
	status=$REDMINE_REVIEW_IN_PROGRESS \
	assigned_to=$REDMINE_USER_ID \
	cf_id=$REDMINE_GIT_REPOS_ID \
	cf_val=$REDMINE_GIT_REPOS_URL \
	task_update || exit 1
	
	PROJECT=$(redmine-get-task-project-identifier --task_id=$TASK)
	TASK_TITLE=$(redmine-get-task-info --task_id=$TASK)
	SLUG_TITLE=$(slug --this "$TASK_TITLE")
	BRNAME="redmine-review-$SLUG_TITLE"
	
	git_refresh_local_repos
	git checkout -b "$BRNAME" "$PR" || exit 1
	git config "redmine.review.current" "$TASK"
	git config "redmine.review.$TASK.pr" "$PR"
	git config "redmine.review.$TASK.title" "$TASK_TITLE"
	git config "redmine.review.$TASK.branch" "$BRNAME"
	git config "redmine.review.$TASK.project" "$PROJECT"

	if ask_question --question="Do you want to rebase before review ?"; then
	    git rebase origin/devel && (git diff --color origin/devel | less -R)
	else
	    git diff --color origin/devel | less -R
	fi
	
	cat <<__EOF__

You can squash / rebase ... 
but please keep the name $BRNAME 
for your branch before further action with git redmine review

To start a review (example):
    git rebase origin/devel
    git diff origin/devel..

If you want to add fixes and send back the branch to the user (if the remote branch is standard):
    git push origin HEAD:redmine-$SLUG_TITLE
or if you have rebase on origin/devel
    git push -f origin HEAD:redmine-$SLUG_TITLE
then
    git redmine review reject

If you want to abort the review
    git redmine review abort

To finish the review:
    git redmine review finish

And don't forget to run your tests before !

__EOF__

	if ask_question --question="Do you want to finish the review now ?"; then
	    REDMINE_CHAIN=1 exec git redmine review finish
	fi

}

function review_abort {
	TASK=$(git config redmine.review.current)

	if [ -z "$TASK" ]; then
	    echo "You have not start any review !"
	    exit 1
	fi
	
	TASK_TITLE=$(git config "redmine.review.$TASK.title")
	BRNAME=$(git config "redmine.review.$TASK.branch")
	PR=$(git config "redmine.review.$TASK.pr")

	if ! ask_question --question="Abort the review of $TASK_TITLE - PR:$PR ?"; then
		exit 1
	fi
	
	git checkout devel
	git branch -D "$BRNAME"
	git config --remove-section "redmine.review.$TASK"
	git config --unset redmine.review.current

	task=$TASK \
	status=$REDMINE_REVIEW_TODO \
	assigned_to=$REDMINE_USER_ID \
	task_update || exit 1

}

function review_reject {
	TASK=$(git config redmine.review.current)

	if [ -z "$TASK" ]; then
	    echo "You have not start any review !"
	    exit 1
	fi
	
	TASK_TITLE=$(git config "redmine.review.$TASK.title")
	BRNAME=$(git config "redmine.review.$TASK.branch")
	PR=$(git config "redmine.review.$TASK.pr")

	if ! ask_question --question="Reject the review of $TASK_TITLE - PR:$PR ?"; then
		exit 1
	fi

	echo "Fetching last developer ..."
	declare -a TASK_DEV=($(redmine-get-task-developers --task_id="$TASK" --status_ids="$REDMINE_TASK_IN_PROGRESS" --ids_only))

	F=$(mktemp /tmp/redmine.XXXXXX)
	vim "$F"

	task=$TASK \
	status=$REDMINE_TASK_TODO \
	assigned_to=${TASK_DEV[0]} \
	notes="This task has been rejected. Here the reasons :

$(cat "$F")
" \
	cf_id=$REDMINE_GIT_PR_ID \
	cf_val=" " \
	task_update || exit 1

	echo ""
	unlink "$F"

	git_refresh_local_repos
	git checkout devel
	git merge origin/devel
	git push origin :tags/"$PR"
	git tag -d "$PR"
	git branch -D "$BRNAME"
	git config --remove-section "redmine.review.$TASK"
	git config --unset "redmine.review.current"

}

function review_finish {
	TASK=$(git config redmine.review.current)

	if [ -z "$TASK" ]; then
	    echo "You have not start any review !"
	    exit 1
	fi
	
	PROJECT=$(git config "redmine.review.$TASK.project")
	TASK_TITLE=$(git config "redmine.review.$TASK.title")
	TASK_DEV=$(redmine-get-task-developers --task_id="$TASK" --status_ids="$REDMINE_TASK_IN_PROGRESS")
	PR=$(git config "redmine.review.$TASK.pr")
	BRNAME=$(git config "redmine.review.$TASK.branch")
	CHANGELOG=$(get_change_log)


	if [ -z "$REDMINE_CHAIN" ]; then
		if ! ask_question --question="Finish the review of $TASK_TITLE - PR:$PR ?"; then
			exit 1
		fi
	fi

	if ! reassigned_this "review" "$PROJECT"; then
		exit 1
	fi

	git_refresh_local_repos
	git checkout devel
	git merge origin/devel
	git merge --no-ff "$BRNAME" -m "Merge $BRNAME"
	echo "    * $TASK_TITLE ($TASK_DEV)" > "$CHANGELOG".new
	touch "$CHANGELOG"
	cat "$CHANGELOG" >> "$CHANGELOG".new
	mv "$CHANGELOG".new "$CHANGELOG"
	vim "$CHANGELOG"
	git add "$CHANGELOG"
	git commit -m "reflect changes" "$CHANGELOG" || true
	git push origin devel
	git push origin :tags/"$PR"
	git tag -d "$PR"
	git branch -D "$BRNAME"
	git config --remove-section "redmine.review.$TASK"
	git config --unset "redmine.review.current"

	task=$TASK \
	status=$REDMINE_RELEASE_TODO \
	assigned_to=$ASSIGNED_TO_ID \
	cf_id=$REDMINE_GIT_PR_ID \
	cf_val=" " \
	task_update
	echo ""

	echo "Removing old pr ..."
	for tag in $(git tag | grep pr-.*-redmine-.*-$TASK-)
	do
    	git push origin :tags/"$tag"
    	git tag -d "$tag"
	done

}