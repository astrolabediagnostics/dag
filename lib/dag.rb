require 'set'

require_relative 'dag/vertex'

class DAG

  Edge = Struct.new(:origin, :destination, :properties)

  #
  # Create a new Directed Acyclic Graph
  #
  # @param [Hash] options configuration options
  # @option options [Module] mix this module into any created +Vertex+
  #
  def initialize(options = {})
    @vertices = []
    @edges = []
    @check_on_add = options[:check_on_add] == nil ? true : options[:check_on_add]
    @checked = true
    @mixin = options[:mixin]
  end

  def vertices
    raise 'graph was not checked before calling vertices' unless @checked
    @vertices
  end

  def edges
    raise 'graph was not checked before calling edges' unless @checked
    @edges
  end

  def add_vertex(payload = {})
    Vertex.new(self, payload).tap {|v|
      v.extend(@mixin) if @mixin
      @vertices << v
    }
  end

  def add_edge(attrs)
    origin = attrs[:origin] || attrs[:source] || attrs[:from] || attrs[:start]
    destination = attrs[:destination] || attrs[:sink] || attrs[:to] || attrs[:end]
    properties = attrs[:properties] || {}
    raise ArgumentError.new('Origin must be a vertex in this DAG') unless
      is_my_vertex?(origin)
    raise ArgumentError.new('Destination must be a vertex in this DAG') unless
      is_my_vertex?(destination)
    raise ArgumentError.new('A DAG must not have cycles') if origin == destination
    if @check_on_add
      raise ArgumentError.new('A DAG must not have cycles') if destination.has_path_to?(origin)
    else
      @checked = false
    end
    Edge.new(origin, destination, properties).tap {|e| @edges << e }
  end

  def subgraph(predecessors_of = [], successors_of = [])


    (predecessors_of + successors_of).each { |v|
      raise ArgumentError.new('You must supply a vertex in this DAG') unless
        is_my_vertex?(v)
      }

    result = self.class.new({mixin: @mixin})
    vertex_mapping = {}

    # Get the set of predecessors verticies and add a copy to the result
    predecessors_set = Set.new(predecessors_of)
    predecessors_of.each { |v| v.ancestors(predecessors_set) }

    predecessors_set.each do |v|
      vertex_mapping[v] = result.add_vertex(payload=v.payload)
    end

    # Get the set of successor vertices and add a copy to the result
    successors_set = Set.new(successors_of)
    successors_of.each { |v| v.descendants(successors_set) }

    successors_set.each do |v|
      vertex_mapping[v] = result.add_vertex(payload=v.payload) unless vertex_mapping.include? v
    end

    # get the unique edges
    edge_set = (
      predecessors_set.flat_map(&:incoming_edges) +
      successors_set.flat_map(&:outgoing_edges)
    ).uniq

    # Add them to the result via the vertex mapping
    edge_set.each do |e|
      result.add_edge(
        from: vertex_mapping[e.origin],
        to: vertex_mapping[e.destination],
        properties: e.properties)
    end

    return result
  end

  # Code taken from:
  # http://www.geeksforgeeks.org/detect-cycle-in-a-graph/
  def is_cyclic_util(v)
    @visited = @visited + [v]
    @rec_stack = @rec_stack + [v]

    for dest in v.outgoing_edges.map(&:destination)
      if !@visited.include?(dest)
        if self.is_cyclic_util(dest)
          return true
        end
      elsif @rec_stack.include?(dest)
        return true
      end
    end

    @rec_stack = @rec_stack - [v]
    return false
  end

  def is_acyclic?
    @checked = true

    @visited = []
    @rec_stack = []
    for v in @vertices
      if !@visited.include?(v)
        if self.is_cyclic_util(v)
          @checked = false
          return false
        end
      end
    end

    return true
  end

  private

  def is_my_vertex?(v)
    v.kind_of?(Vertex) and v.dag == self
  end

end
