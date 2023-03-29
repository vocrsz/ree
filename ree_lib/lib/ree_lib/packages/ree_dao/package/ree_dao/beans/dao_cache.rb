class ReeDao::DaoCache
  include Ree::BeanDSL

  bean :dao_cache do
    singleton
    after_init :setup
  end

  def setup
    @thread_groups = {}
  end

  def add_thread_group_cache(thread_group)
    @thread_groups[thread_group.object_id] ||= {}
  end

  def drop_thread_group_cache(thread_group)
    @thread_groups.delete(thread_group.object_id)
  end

  def get(table_name, primary_key)
    add_thread_group_cache(current_thread_group)
    add_table_name(table_name)

    @thread_groups[current_thread_group.object_id][table_name][primary_key] 
  end

  def set(table_name, primary_key, data)
    add_thread_group_cache(current_thread_group)
    add_table_name(table_name)
    add_primary_key(table_name, primary_key)
   
    @thread_groups[current_thread_group.object_id][table_name][primary_key] = data
  end

  def drop_table_cache(table_name)
    add_thread_group_cache(current_thread_group)
    @thread_groups[current_thread_group.object_id].delete(table_name)
  end

  private

  def current_thread_group
    Thread.current.group
  end

  def add_table_name(thread_group = Thread.current.group, table_name)
    @thread_groups[thread_group.object_id][table_name] ||= {}
  end

  def add_primary_key(thread_group = Thread.current.group, table_name, primary_key)
     @thread_groups[thread_group.object_id][table_name][primary_key] ||= {}
  end
end