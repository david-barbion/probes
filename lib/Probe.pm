package Probe;
use Mojo::Base 'Mojolicious';
#use Scalar::Util 'weaken';

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
    $self->secret( $config->{ secret } || 'Xwyfe-_d:yGDr+p][Vs7Kk+e3mmP=c_|s7hvExF=b|4r4^gO|' );

    # startup database connection
    $self->plugin( 'database', $config->{ database } || {} );

    # Load HTML Messaging plugin
    $self->plugin('messages');

    # Documentation browser under "/perldoc" (this plugin requires Perl 5.10)
    $self->plugin('PODRenderer');

    # Routes
    my $r = $self->routes;

    # Home page and set management (Probe::Site)
    $r->route('/')->to('site#home')->name('home');

    # Probe management (Probe::Probes)
    my $rw = $r->waypoint('/probes')         ->to('probes#list')   ->name('probes_list'); # link to add
    $rw->route('/add')                       ->to('probes#add')    ->name('probes_add');
    $rw->route('/:id', id => qr/\d+/)   ->to('probes#show')   ->name('probes_show');
    $rw->route('/:id/edit', id => qr/\d+/)   ->to('probes#edit')   ->name('probes_edit');
    $rw->route('/:id/remove', id => qr/\d+/) ->to('probes#remove') ->name('probes_remove');


    # Gestion de tous les graphs même les customs graphs (Probe::Graphs)
#    my $gw = $r->waypoint('/graphs')         ->to('graphs#list')   ->name('graphs_list');
#    $gw->route('/add')                       ->to('graphs#add')    ->name('graphs_add');
#    $gw->route('/:id', id => qr/\d+/)        ->to('graphs#show')   ->name('graphs_show');
#    $gw->route('/:id/edit', id => qr/\d+/)   ->to('graphs#edit')   ->name('graphs_edit');
#    $gw->route('/:id/delete', id => qr/\d+/) ->to('graphs#remove') ->name('graphs_remove');


    # Print and manipulate graphs for a specified set (Probe::Draw)
    $r->route('/draw/data')   ->via('post')              ->to('draw#data')   ->name('draw_data');
    my $dw = $r->waypoint('/draw/:nsp')                  ->to('draw#list')      ->name('draw_list');
    $dw->route('/save')       ->via('post')              ->to('draw#save_list') ->name('draw_list_save');
    $dw->route('/orphans')                               ->to('draw#orphans')   ->name('draw_orphans');
    $dw->route('/show')                                  ->to('draw#show')      ->name('draw_show');
    $dw->route('/add')                                   ->to('draw#add')       ->name('draw_add');
    $dw->route('/edit/:id', id => qr/\d+/)               ->to('draw#edit')      ->name('draw_edit');
    $dw->route('/remove/:id', id => qr/\d+/)             ->to('draw#remove')    ->name('draw_remove');

}

1;
