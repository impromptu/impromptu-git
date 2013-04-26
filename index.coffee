gift = require 'gift'

module.exports = (Impromptu) ->
  @name 'git'

  @register 'isRepo', (done) ->
    @exec 'git rev-parse --is-inside-work-tree 2>/dev/null', (err, result) ->
      done err, result.trim() is 'true'

  @register 'root', (done) ->
    @get 'isRepo', (err, result) =>
      return done err, false unless result

      @exec 'git rev-parse --show-toplevel', (err, result) ->
        done err, result.trim()

  @register 'repo', (done) ->
    @get 'root', (err, result) ->
      if err or not result
        done err, result
      else
        done err, gift result

  @register 'branch', (done) ->
    @get 'repo', (err, repo) ->
      if err or not repo
        return done err, ''

      repo.branch (_err, heads) ->
        done _err, heads.name

  @register 'status', (done) ->
    @get 'repo', (err, repo) ->
      if err or not repo
        return done err, repo

      repo.status (_err, status) ->
        results =
          untracked: []
          modified: []
          deleted: []

        for file, details of status.files
          if details.tracked is off
            results.untracked.push file
          else if details.type is 'M'
            results.modified.push file
          else if details.type is 'D'
            results.deleted.push file

        done _err, results

  ['untracked', 'modified', 'deleted'].forEach (method) =>
    @register method, (done) ->
      @get 'status', (err, status) ->
        if err or not status
          return done err, status
        done err, status[method].length

