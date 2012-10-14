package Probe;
use Mojo::Base 'Mojolicious';

# This method will run once at server start
sub startup {
    my $self = shift;

    # register Helpers plugins namespace
    $self->plugins->namespaces( [ "Helpers", @{ $self->plugins->namespaces } ] );

    # setup charset
    $self->plugin( charset => { charset => 'utf8' } );

    # load configuration
    my $config_file = $self->home.'/probe.conf';
    my $config = $self->plugin( 'JSONConfig' => { file => $config_file });

    # setup secret passphrase XXX
    $self->secret( $config->{secret} || 'Xwyfe-_d:yGDr+p][Vs7Kk+e3mmP=c_|s7hvExF=b|4r4^gO|' );

    # startup database connection
    $self->plugin( 'database', $config->{ database } || {} );

    # Load HTML Messaging plugin
    $self->plugin('messages');

    $self->plugin('menu');

    $self->plugin('permissions');

    # Documentation browser under "/perldoc" (this plugin requires Perl 5.10)
    $self->plugin('PODRenderer');

    # Add a perl mime type for the script generation
    $self->types->type(pl => 'application/x-perl');

    # CGI pretty URLs
    if ($config->{rewrite}) {
	$self->hook( before_dispatch => sub {
			 my $self = shift;
			 $self->req->url->base(Mojo::URL->new($config->{base_url}));
		     });
    }

    # Routes
    my $r = $self->routes;
    my $ra = $r->bridge->to('users#check');

    # Home page
    $ra->route('/')         ->to('site#home')     ->name('site_home');
    $ra->route('/help')     ->to('site#help')     ->name('site_help');

    # User stuff
    $r->route('/login')     ->to('users#login')     ->name('users_login');
    $ra->route('/logout')   ->to('users#logout')    ->name('users_logout');
    $r->route('/register')  ->to('users#register')  ->name('users_register');
    $ra->route('/profile')  ->to('users#profile')   ->name('users_profile');

    # Admin
    # Users
    # Permissions
    $ra->route('/users')                           ->to('users#list')   ->name('users_list');
    $ra->route('/users/add')                       ->to('users#add')    ->name('users_add');
    $ra->route('/users/:id', id => qr/\d+/)        ->to('users#show')   ->name('users_show');
    $ra->route('/users/:id/edit', id => qr/\d+/)   ->to('users#edit')   ->name('users_edit');
    $ra->route('/users/:id/remove', id => qr/\d+/) ->to('users#remove') ->name('users_remove');

    # Results management
    $ra->route('/results')                           ->to('results#list')   ->name('results_list'); # a table with all results available to the user
    $ra->route('/results/upload')                    ->to('results#upload') ->name('results_upload');
    $ra->route('/results/:id', id => qr/\d+/)        ->to('results#show')   ->name('results_show'); # the info on the results + linked reports + linked graphs
    $ra->route('/results/:id/remove', id => qr/\d+/) ->to('results#remove') ->name('results_remove');

    # Script management
    $ra->route('/scripts')                           ->to('scripts#list')   ->name('scripts_list');
    $ra->route('/scripts/add')                       ->to('scripts#add')    ->name('scripts_add');
    $ra->route('/scripts/:id', id => qr/\d+/)        ->to('scripts#show')   ->name('scripts_show');
    $ra->route('/scripts/:id/edit', id => qr/\d+/)   ->to('scripts#edit')   ->name('scripts_edit');
    $ra->route('/scripts/:id/remove', id => qr/\d+/) ->to('scripts#remove') ->name('scripts_remove');
    $ra->route('/scripts/:id/get', id => qr/\d+/)    ->to('scripts#download')->name('scripts_download');

    # Probe management (Probe::Probes)
    $ra->route('/probes')                           ->to('probes#list')   ->name('probes_list');
    $ra->route('/probes/add')                       ->to('probes#add')    ->name('probes_add');
    $ra->route('/probes/:id', id => qr/\d+/)        ->to('probes#show')   ->name('probes_show');
    $ra->route('/probes/:id/edit', id => qr/\d+/)   ->to('probes#edit')   ->name('probes_edit');
    $ra->route('/probes/:id/remove', id => qr/\d+/) ->to('probes#remove') ->name('probes_remove');

    # Graph management
    $ra->route('/graphs')                           ->to('graphs#list')   ->name('graphs_list');
    $ra->route('/graphs/add')                       ->to('graphs#add')    ->name('graphs_add');
    $ra->route('/graphs/:id', id => qr/\d+/)        ->to('graphs#show')   ->name('graphs_show');
    $ra->route('/graphs/:id/edit', id => qr/\d+/)   ->to('graphs#edit')   ->name('graphs_edit');
    $ra->route('/graphs/:id/remove', id => qr/\d+/) ->to('graphs#remove') ->name('graphs_remove');
    $ra->route('/graphs/data')   ->via('post')      ->to('graphs#data')   ->name('graphs_data');

    # Reports
    $ra->route('/reports')                           ->to('reports#list')      ->name('reports_list');
    $ra->route('/reports/add')                       ->to('reports#add')       ->name('reports_add');
    $ra->route('/reports/:id', id => qr/\d+/)        ->to('reports#show')      ->name('reports_show');
    $ra->route('/reports/:id/edit', id => qr/\d+/)   ->to('reports#edit')      ->name('reports_edit');
    $ra->route('/reports/:id/remove', id => qr/\d+/) ->to('reports#remove')    ->name('reports_remove');

}

1;


