Request = require "./request"
API = require "./api"
Action = require("./action")

module.exports = class Patchboard
  @Request = Request

  @discover: (args...) ->
    if args.length == 2
      [url, callback] = args
      options = {}
    else if args.length == 3
      [url, options, callback] = args

    if url.constructor != String
      throw new Error("Discovery URL must be a string")

    req =
      url: url
      method: "GET"
      headers:
        "Accept": "application/json"

    new Request req, (error, response) =>
      if error?
        callback error
      else
        if response.data?
          client = new @(response.data, options)
          callback null, client
        else
          callback new Error "Unparseable response body"



  constructor: (api, @options={}) ->
    {@authorizer, context} = @options
    @context_creator = context || Object
    @api = new API(api)

    @create_resource_constructors(@api.resources, @api.mappings)
    client = @spawn()
    @resources = client.resources
    @context = client.context

  spawn: (context) ->
    context ?= new @context_creator()
    new Client(@, context, @api)

  class Client

    constructor: (main, @context, api) ->
      Object.defineProperty @, "main", main
      @resources = @create_endpoints(@context, api.mappings)

    spawn: (context) ->
      @main.spawn(context)





    # Create resource instances and constructor-helpers using the URLs supplied
    # in the API mappings.
    create_endpoints: (context, mappings) ->
      endpoints = {}
      for name, mapping of mappings
        do (name, mapping) =>
          {url, query, path, template} = mapping
          constructor = mapping.constructor
          if template? || query?
            endpoints[name] = (params={}) ->
              new constructor context, {url: mapping.generate_url(params)}
          else if path?
            endpoints[name] = new constructor context, url: mapping.generate_url()
          else if url?
            endpoints[name] = new constructor context, url: url
          else
            console.error "Unexpected mapping:", name, mapping
      endpoints

  create_resource_constructors: (definitions, mappings) ->
    constructors = {}

    for name, mapping of mappings
      definition = mapping.resource
      constructor = @resource_constructor({mapping, definition})
      mapping.constructor = constructor
      constructors[name] = constructor

      if definition.aliases?
        for alias in definition.aliases
          constructors[alias] = constructor

    constructors

  resource_constructor: ({mapping, definition}) ->
    client = @
    constructor = (@context, data={}) ->
      if data?.constructor == String
        # for cases like: resource("http://something.com/foo")
        @url = data
      else
        for key, value of data
          @[key] = value
      return @

    constructor.prototype._actions = {}
    constructor.prototype.resource_type = definition.name

    # Hide the Patchboard client from such things as console.log
    Object.defineProperty constructor.prototype, "patchboard_client",
      value: @
      enumerable: false

    for name, def of definition.actions
      do (name, def) ->
        action = constructor.prototype._actions[name] = new Action(client, name, def)
        constructor.prototype[name] = (args...) ->
          action.request(@, @url, args...)

    # Mix in default resource methods
    for name, method of @resource_methods
      constructor.prototype[name] = method

    constructor


  resource_methods:

    # returns a string that (when logged to console) can be used as the
    # curl command that exactly represents this action.
    curl: (name, args...) ->
      action = @_actions[name]
      request = action.create_request(@url, args...)

      {method, url, headers, body} = request
      agent = headers["User-Agent"]
      command = []
      command.push "curl -v -A '#{agent}' -X #{method}"
      for header, value of headers when header != "User-Agent"
        command.push "  -H '#{header}: #{value}'"

      if body?
        command.push "  -d #{JSON.stringify(body)}"
      command.push "  #{url}"
      command.join(" \\\n")

  # end resource_methods




