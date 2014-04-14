class cikl::logstash (
  $elasticsearch_template = '/etc/logstash/elasticsearch-cikl-template.json'
) {
  require cikl::repositories
  require cikl::elasticsearch
  include cikl::common_packages
  include cikl::rabbitmq

  class { '::logstash':
    require => [ 
      Class['cikl::repositories', 'rabbitmq'], 
      Package['cikl::common_packages::java7']
    ]
  }
  Service['elasticsearch'] -> Service['logstash']
  Service['rabbitmq-server'] -> Service['logstash']

  file { 'elasticsearch-cikl-template': 
    path    => $elasticsearch_template,
    owner   => "root",
    group   => "root",
    mode    => '0644',
    content => template('cikl/elasticsearch-cikl-template.json.erb')
  }

  ::logstash::configfile { 'input-rabbitmq':
    content => template('cikl/logstash-input-rabbitmq.conf.erb'),
    order   => 10
  }

  ::logstash::configfile { 'filter-event':
    content => template('cikl/logstash-filter-event.conf.erb'),
    order   => 20
  }

  ::logstash::configfile { 'output-elasticsearch':
    content => template('cikl/logstash-output-event.conf.erb'),
    require => File['elasticsearch-cikl-template'],
    order   => 30
  }

#logstash::configfile { 'output-resolve':
#  content => template('cikl/logstash-output-resolve.conf.erb'),
#  order   => 30
#}
}

