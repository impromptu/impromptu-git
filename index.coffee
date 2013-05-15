getStatuses = (porcelainStatus) ->
  PORCELAIN =
    staged   : /^[^\?\s]/  # Leading non-whitespace that is not a question mark
    unstaged : /\S$/       # Trailing non-whitespace
    added    : /A|\?\?/    # Any "A" or "??"
    modified : /M/         # Any "M"
    deleted  : /D/         # Any "D"

  porcelainStatus.replace(/\s+$/, '').split('\0').map (line) ->
    status = line.substring 0, 2

    path: line.slice 3
    properties: (prop for prop, regex of PORCELAIN when regex.test status)


module.exports = (Impromptu, register, git) ->
  # Helper to figure out if we're in a repo at all
  register 'isRepo',
    update: (done) ->
      command = '([ -d .git ] || git rev-parse --git-dir >/dev/null 2>&1)'
      Impromptu.exec command, (err) ->
        done err, ! err

  # Root path to the repository
  register 'root',
    update: (done) ->
      command = 'git rev-parse --show-toplevel 2>/dev/null'
      Impromptu.exec command, (err, result) ->
        if err
          done err, null
        else
          done err, result.trim()

  # Branch name
  # Returns commit hash when head is detached
  # Returns null in newly-initialized repos (note that isRepo() still returns true in this case)
  register 'branch',
    update: (done) ->
      command = 'git rev-parse --abbrev-ref HEAD 2>/dev/null'
      Impromptu.exec command, (err, result) ->
        return done err, null if err

        result = result.trim()
        return done err, result unless result is 'HEAD'

        Impromptu.exec 'git rev-parse --short HEAD', (_err, _result) ->
          done _err, _result

  # Short commit hash
  register 'commit',
    update: (done) ->
      Impromptu.exec 'git rev-parse --short HEAD 2>/dev/null', (err, result) ->
        if err
          done err, null
        else
          done err, result.trim()

  # Determine whether the repo is currently in a detached head state
  # This happens when you checkout, for example, a commit hash
  register 'isDetachedHead',
    update: (done) ->
      Impromptu.exec 'git symbolic-ref HEAD 2>/dev/null', (err) ->
        done err, !! err

  register 'remoteBranch',
    update: (done) ->
      tracking_branch_command = "git for-each-ref --format='%(upstream:short)' $(git symbolic-ref -q HEAD)"
      Impromptu.exec tracking_branch_command, (err, result) ->
        if result
          done err, result.trim()
        else
          done err, null

  # Returns an object with 'ahead' and 'behind' keys
  # Each has a count of commits that your repo is ahead/behind its upstream
  #
  # This command *must* be passed through a formatter before its displayed
  register '_aheadBehind',
    update: (done) ->
      git.remoteBranch (err, remoteBranch) ->
        return done err, null unless remoteBranch

        command = "git rev-list --left-right --count #{remoteBranch.trim()}...HEAD"
        Impromptu.exec command, (err, result) ->
          return done err, null if err
          data = result.trim().split(/\s+/).map (value) ->
            parseInt value, 10

          done err, {behind: data[0], ahead: data[1]}

  # Get the number of commits you're ahead of the remote
  register 'ahead',
    update: (done) ->
      git._aheadBehind (err, aheadBehind) ->
        done err, aheadBehind?.ahead

  # Get the number of commits you're behind the remote
  register 'behind',
    update: (done) ->
      git._aheadBehind (err, aheadBehind) ->
        done err, aheadBehind?.behind


  class Statuses
    constructor: (@statuses) ->
      properties = ['added', 'modified', 'deleted', 'staged', 'unstaged']

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
      results.join ' '

    @formatters:
      added: ->
        if @length then "+#{@length}" else ""

      modified: ->
        if @length then "∆#{@length}" else ""

      deleted: ->
        if @length then "-#{@length}" else ""

  # Returns an array of objects with 'path', 'code', 'staged', 'state'
  #
  # This command *must* be passed through a formatter before its displayed
  register '_status',
    update: (done) ->
      Impromptu.exec 'git status --porcelain -z 2>/dev/null', (err, result) ->
        return done err, null if err
        statuses = getStatuses result
        done null, new Statuses statuses

  # Register object and string methods for filtering the statuses.
  #
  # Object methods: `_staged`, `_unstaged`, `_added`, `_modified`, `_deleted`
  # String methods: `staged`, `unstaged`, `added`, `modified`, `deleted`
  #
  # Strings are formatted as "∆2 +1 -3" by default.
  ['staged', 'unstaged', 'added', 'modified', 'deleted'].forEach (type) ->
    # Get an object that has filtered the statuses by type.
    register "_#{type}",
      update: (done) ->
        git._status (err, statuses) ->
          done err, new Statuses statuses[type]

    # Get a string that represents the status.
    # Format: "∆2 +1 -3"
    register type,
      update: (done) ->
        git["_#{type}"] (err, statuses) ->
          done err, statuses.toString()

  register 'fetch',
    cache: 'repository'
    expire: 60
    update: (done) ->
      git.isRepo (err, isRepo) ->
        return done err, isRepo unless isRepo

        Impromptu.exec 'git fetch --all', (err, results) ->
          done err, results

  # Register the git repository.
  @repository.register 'git',
    root: git.root
    branch: git.branch
    commit: git.commit
