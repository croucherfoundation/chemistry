# Model lifecycle:
#
# 1. init sets up a promise of readiness
# 2. build sets up attributes and collections
# 3. load fetches data from the API
# 4. loaded resolves the promise, which triggers populate
# 5. populate places received data into attributes and collections
# 6. save
#
# Call `model.ready()` to access the readiness promise after construction
# or call `whenLoaded(function)` to attach more callbacks. They will
# fire after population and receive the fetched data as first argument.
#
class Cms.Model extends Backbone.Model
  autoload: false
  savedAttributes: []
  savedAssociations: []

  initialize: (opts={}) ->
    @_class_name = @constructor.name
    @_original_attributes = {}

    @prepareLoader()
    @load() if @autoload

    ## Build
    # is a preparatory step that usually sets up hasMany collections and belongsTo associations.
    #
    @build()

    ## Saving
    #
    # every model carries a 'changed' marker and on every significant change we check present attributes against
    # original attributes and set the 'changed' marker accordingly.
    #
    @prepareSaver()
    @resetOriginalAttributes()
    @set 'changed', false
    @on "change", @changedIfSignificant
    @on "sync", @resetOriginalAttributes


  ## Load and save
  # Loading is promised. Actions that should be taken only when a model needs no further fetching
  # can be triggered safely with `model.loadAnd(function)` or `model.whenLoaded(function)`,
  # which does not itself trigger loading but will call back when loading is complete.
  # The loaded promise is resolved when we are fetched either individually or in a collection.
  #
  prepareLoader: =>
    @_loaded?.cancel()
    @_loaded = $.Deferred()
    @_loaded.resolve() if @isNew()
    @_loading = false

  prepareSaver: =>
    @_saved = $.Deferred()
    @_saved.resolve() unless @isNew()
    @_saving = false

  loadAnd: (fn) =>
    @_loaded.done fn
    @load() unless @_loading or @isLoaded()

  whenLoaded: (fn) =>
    @_loaded.done fn

  whenFailed: (fn) =>
    @_loaded.fail fn

  isLoaded: =>
    @_loaded.isResolved()

  load: =>
    unless @_loading or @isLoaded()
      @_loading = true
      @fetch(error: @notLoaded).done(@loaded)
    @_loaded.promise()
  
  loaded: (data) =>
    @_loading = false
    @_saved.resolve()
    @_loaded.resolve(data)

  notLoaded: (error) =>
    @_loading = false
    @_loaded.reject(error)

  reload: ->
    @prepareLoader()
    @load()

  loadIfBare: =>
    @load() if @isBare()

  # true if we have only an id, which would mean we are meant to be fetched.
  isBare: =>
    bare_attributes = {}
    bare_attributes[@idAttribute] = @get(@idAttribute)
    _.isEqual @attributes, bare_attributes


  ## Construction
  #
  build: =>
    # usually this is all about associates:
    # @hasMany 'sections'
    # @belongsTo 'image'
    # etc

  parse: (data) =>
    # you can modify `data` in populate,
    # or return false to prevent the usual parse from being called at all.
    # but you don't really want to override `parse`
    if @populate(data)
      @_original_attributes = _.pick @attributes, @savedAttributes
      data

  populate: (data) =>
    # @things.reset(data.things)
    @momentify(data)
    true

  momentify: (data) =>
    for col in ["created_at", "updated_at", "published_at", "deleted_at"]
      if string = data[col]
        @set col, new Date(string)
        delete data[col]


  ## Associations
  #
  # belongsTo sets up the listeners involved in maintaining a one-to-one association.
  # It allows us to fetch and save an object_id while working in the UI with the instantiated object.
  # The object has to be gettable from the supplied collection using the object_id.
  #
  # The UI and any view bindings should always use the object_attribute
  # (eg set or bind to 'video', not 'video_id').
  # The id_attribute is only for use upwards, to and from the API.
  #
  belongsTo: (object_attribute, id_attribute, collection) =>
    id_attribute ?= "#{object_attribute}_id"
    model_class = Cms.Models[_.camelize(object_attribute)]

    # For the usual situation when an associate is sent down just as eg. section_type_id
    if object_id = @get(id_attribute)
      if collection
        @set object_attribute, collection.findOrAdd(object_id), silent: true
      else
        object = new model_class({id: object_id})
        @set object_attribute, object

    # For the unusual case where a whole nested object is sent down.
    else if object_data = @get(object_attribute)
      object = new model_class(object_data)
      @set object_attribute, object, silent: true
      @set id_attribute, object.get('id'), silent: true

    # In the UI we always assign the object
    @on "change:#{object_attribute}", @assignObject

  assignObject: (me, it, options) =>
    if it
      # something has been assigned
      if id = it.get('id')
        # ...that already exists and has an ID.
        @set id_attribute, id, stickitChange: true
      else
        # ...that is new and ought to get an ID soon.
        it.once "change:id", (it_again, new_id) =>
          @set id_attribute, new_id, stickitChange: true
    else
      # `nothing` has been assigned
      @set id_attribute, null, stickitChange: true


  # hasMany sets up the listeners involved in maintaining a one to many association
  # and provides all the logic of receiving and saving nested collection data.
  #
  # In the UI we should always use the attached collection.
  # On load and save it is a nested list of attribute hashes.
  #
  hasMany: (association_name, options={}) =>
    class_name = options.collection_class ? _.capitalize(s.camelize(association_name))
    collection_class = Cms.Collections[class_name]
    default_options = paginated: false

    # create collection from the initial association data
    @[association_name] = new collection_class null, _.extend(default_options, options)

    # Listen for changes to the association data and repopulate the attached collection
    @on "change:#{association_name}", (model, data) =>
      data ?= @get(association_name) || []
      @[association_name].set data,
        add: true
        remove: true
        merge: true
        reset: true
      @set association_name, null, silent: true
      @[association_name].loaded()

    # Trigger the change mechanism to initialize the attached collection with the initial association data
    @trigger "change:#{association_name}"

    # Listen for changes to the attached collection.
    @[association_name].on "change:changed add remove clear", (e) =>
      @_changed_associations.push(association_name) unless association_name in @_changed_associations
      @changedIfSignificant()

  toJSONWithRootAndAssociations: =>
    root = @singularName()
    json = {}
    json[root] = @toJSONWithAssociations()
    json

  toJSONWithAssociations: =>
    json = {}
    if attributes = _.result @, "savedAttributes"
      for att in attributes
        json[att] = @get(att)
    else
      json = @toJSON()
    if associations = _.result @, "savedAssociations"
      for association_name in associations
        json[association_name] = @[association_name].toJSONWithAssociations()
    json


  ## Save progress
  # Callbacks that capture progress values for display purposes.
  #
  startProgress: () =>
    @set("progress", 0)
    @set("progressing", true)

  setProgress: (p) =>
    if p.lengthComputable
      perc = Math.round(10000 * p.loaded / p.total) / 100.0
      @set("progress", perc)

  finishProgress: () =>
    @set("progress", 100)
    @set("progressing", false)


  ## Change monitoring
  #
  markAsChanged: (e) =>
    @set "changed", true
  
  markAsUnchanged: () =>
    @set "changed", false
  
  resetOriginalAttributes: =>
    @_original_attributes = _.pick @attributes, @savedAttributes

  changedIfSignificant: (model, options) =>
    if options.stickitChange?
      @set "changed", not _.isEmpty @significantChangedAttributes()

  significantChangedAttributes: () =>
    significantly_changed = _.pick @changedAttributes(), @savedAttributes
    actually_changed_keys = _.filter _.keys(significantly_changed), (k) =>
      significantly_changed[k] isnt @_original_attributes[k]
    _.pick significantly_changed, actually_changed_keys


  ## Structural
  #
  className: =>
    @_class_name#.replace("Base", "")

  label: =>
    @_class_name.toLowerCase()

  singularName: =>
    _.underscored @className()

  pluralName: =>
    @singularName() + 's'      # well, it works.


  ## Housekeeping
  #
  touch: () =>
    @set 'updated_at', moment(),
      stickitChange: true

  isDestroyed: () =>
    @get('deleted_at')

  destroyReversibly: () =>
    unless @get('deleted_at')
      @set('deleted_at', moment())
      @markAsChanged()

  log: ->
    _cms.log "[#{@constructor.name}]", arguments...
