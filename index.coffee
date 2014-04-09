impromptu = require 'impromptu'
fs = require 'fs'
path = require 'path'

getStatuses = (porcelainStatus) ->
  PORCELAIN =
    staged   : /^[^\?\s]/  # Leading non-whitespace that is not a question mark
    unstaged : /\S$/       # Trailing non-whitespace
    added    : /A|\?\?/    # Any "A" or "??"
    modified : /M/         # Any "M"
    deleted  : /D/         # Any "D"
    renamed  : /R/         # Any "R"

  porcelainStatus.replace(/\s+$/, '').split('\0').map (line) ->
    status = line.substring 0, 2

    path: line.slice 3
    properties: (prop for prop, regex of PORCELAIN when regex.test status)

module.exports = impromptu.plugin.create (git) ->
  # Helper to figure out if we're in a repo at all
  git.register 'isRepo',
    update: (done) ->
      command = '([ -d .git ] || [[ "true" == `git rev-parse --is-inside-work-tree 2>&1` ]])'
      impromptu.exec command, (err) ->
        done err, ! err

  # Root path to the repository
  git.register 'root',
    update: (done) ->
      command = 'git rev-parse --show-toplevel 2>/dev/null'
      impromptu.exec command, (err, result) ->
        if err
          done err, null
        else
          done err, result.trim()

  # Branch name
  # Returns commit hash when head is detached
  # Returns null in newly-initialized repos (note that isRepo() still returns true in this case)
  git.register 'branch',
    update: (done) ->
      command = 'git rev-parse --abbrev-ref HEAD 2>/dev/null'
      impromptu.exec command, (err, result) ->
        return done err, null if err

        result = result.trim()
        return done err, result unless result is 'HEAD'

        impromptu.exec 'git rev-parse --short HEAD', (_err, _result) ->
          done _err, _result

  # Short commit hash
  git.register 'commit',
    update: (done) ->
      impromptu.exec 'git rev-parse --short HEAD 2>/dev/null', (err, result) ->
        if err
          done err, null
        else
          done err, result.trim()

  # Determine whether the repo is currently in a detached head state
  # This happens when you checkout, for example, a commit hash
  git.register 'isDetachedHead',
    update: (done) ->
      impromptu.exec 'git symbolic-ref HEAD 2>/dev/null', (err) ->
        done err, !! err

  git.register 'isRebasing',
    update: (done) ->
      git.root (err, root) ->
        return done err if err
        impromptu.exec "test -d #{root}/.git/rebase-merge -o -d #{root}/.git/rebase-apply", (err) ->
          if not err
            done null, true
          else if err.code is 1
            done null, false
          else
            done err, null

  git.register 'remoteBranch',
    update: (done) ->
      tracking_branch_command = "git for-each-ref --format='%(upstream:short)' $(git symbolic-ref -q HEAD)"
      impromptu.exec tracking_branch_command, (err, result) ->
        if result
          done err, result.trim()
        else
          done err, null

  # Returns an object with 'ahead' and 'behind' keys
  # Each has a count of commits that your repo is ahead/behind its upstream
  #
  # This command *must* be passed through a formatter before its displayed
  git.register '_aheadBehind',
    update: (done) ->
      git.fetch (err) ->
        return done err, null if err

        git.remoteBranch (err, remoteBranch) ->
          return done err, null unless remoteBranch

          command = "git rev-list --left-right --count #{remoteBranch.trim()}...HEAD"
          impromptu.exec command, (err, result) ->
            return done err, null if err
            data = result.trim().split(/\s+/).map (value) ->
              parseInt value, 10

            done err, {behind: data[0], ahead: data[1]}

  # Get the number of commits you're ahead of the remote
  git.register 'ahead',
    update: (done) ->
      git._aheadBehind (err, aheadBehind) ->
        done err, aheadBehind?.ahead

  # Get the number of commits you're behind the remote
  git.register 'behind',
    update: (done) ->
      git._aheadBehind (err, aheadBehind) ->
        done err, aheadBehind?.behind


  class Statuses
    constructor: (@statuses) ->
      properties = ['added', 'modified', 'deleted', 'renamed', 'staged', 'unstaged']

      # Create status arrays.
      for property in properties
        @[property] = []

      # Bind array formatters.
      for property, formatter of Statuses.formatters
        @[property].toString = formatter if @[property]

      # Populate status arrays.
      for status in @statuses
        for property in properties
          @[property].push status if status.properties.indexOf(property) > -1

    toString: ->
      results = []
      results.push @modified if @modified.length
      results.push @added if @added.length
      results.push @deleted if @deleted.length
      results.push @renamed if @renamed.length
      results.join ' '

    @formatters:
      added: ->
        if @length then "+#{@length}" else ""

      modified: ->
        if @length then "∆#{@length}" else ""

      deleted: ->
        if @length then "-#{@length}" else ""

      renamed: ->
        if @length then "→#{@length}" else ""

  # Returns an array of objects with 'path', 'code', 'staged', 'state'
  #
  # This command *must* be passed through a formatter before its displayed
  git.register '_status',
    update: (done) ->
      impromptu.exec 'git status --porcelain -z 2>/dev/null', (err, result) ->
        return done err, null if err
        statuses = getStatuses result
        done null, new Statuses statuses

  # Register object and string methods for filtering the statuses.
  #
  # Object methods: `_staged`, `_unstaged`, `_added`, `_modified`, `_deleted`, `_renamed`
  # String methods: `staged`, `unstaged`, `added`, `modified`, `deleted`, `renamed`
  #
  # Strings are formatted as "∆2 +1 -3" by default.
  ['staged', 'unstaged', 'added', 'modified', 'deleted', 'renamed'].forEach (type) ->
    # Get an object that has filtered the statuses by type.
    git.register "_#{type}",
      update: (done) ->
        git._status (err, statuses) ->
          done err, new Statuses statuses[type]

    # Get a string that represents the status.
    # Format: "∆2 +1 -3 →2"
    git.register type,
      update: (done) ->
        git["_#{type}"] (err, statuses) ->
          done err, statuses.toString()

  git.register 'fetch',
    cache: 'repository'
    expire: 60
    update: (done) ->
      git.isRepo (err, isRepo) ->
        return done err, isRepo unless isRepo

        impromptu.exec 'git fetch --all', (err, results) ->
          done err, results

  git.register 'stashCount',
    update: (done) ->
      git.root (err, root) ->
        return done err if err

        fs.exists path.join(root, '.git/logs/refs/stash'), (exists) ->
          return done null, 0 unless exists

          impromptu.exec "wc -l #{path.join root, '.git/logs/refs/stash'}", (err, count) ->
            done err, parseInt count.trim(), 10

  git.register 'remoteUrl',
    update: (done) ->
      impromptu.exec 'git config --get remote.origin.url', done

  # Register the git repository.
  impromptu.repository.register 'git',
    root: git.root
    branch: git.branch
    commit: git.commit
