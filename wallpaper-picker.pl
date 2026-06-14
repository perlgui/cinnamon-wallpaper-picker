#!/usr/bin/env perl
use strict;
use warnings;

our $VERSION = '1.0.0';

package WallpaperPicker;
use Moo;
use Gtk3 '-init';
use Glib qw(TRUE FALSE);
use File::Glob ':glob';
use File::Path qw(make_path);
use Digest::SHA qw(sha1_hex);

use constant {
    DEFAULT_THUMB_HEIGHT    => 300,
    DEFAULT_THUMB_WIDTH     => 480,
    DEFAULT_PADDING         => 16,
    DEFAULT_FADE_STEPS      => 20,
    DEFAULT_FADE_INTERVAL   => 30,
    STRIP_LABEL_HEIGHT      => 60,
    PROGRESS_BAR_H          => 4,
    PROGRESS_BAR_MARGIN     => 2,
    SELECTION_INSET         => 4,
    SELECTION_OUTSET        => 8,
    BG_R                    => 0.08,
    BG_G                    => 0.08,
    BG_B                    => 0.10,
    BG_A                    => 0.92,
    PROG_R                  => 0.6,
    PROG_G                  => 0.8,
    PROG_B                  => 1.0,
    PROG_A                  => 0.7,
    SEL_FILL_R              => 0.95,
    SEL_FILL_G              => 0.95,
    SEL_FILL_B              => 1.0,
    SEL_FILL_A              => 0.25,
    SEL_LINE_R              => 0.6,
    SEL_LINE_G              => 0.8,
    SEL_LINE_B              => 1.0,
    SEL_LINE_A              => 0.9,
    SEL_LINE_WIDTH          => 2.5,
    THUMB_UNLOADED_R        => 0.2,
    THUMB_UNLOADED_G        => 0.2,
    THUMB_UNLOADED_B        => 0.25,
    THUMB_UNLOADED_A        => 1.0,
    COAST_TIMER_MS          => 16,
    COAST_DECAY             => 0.85,
    COAST_MIN_VEL           => 2.0,
    SETTLE_DELAY_MS         => 150,
    SETTLE_TIMER_MS         => 16,
    SETTLE_EASE             => 0.2,
    SETTLE_THRESHOLD        => 0.5,
    SCROLL_STEP_DIVISOR     => 3,
    JPEG_QUALITY            => '100',
    OPACITY_MAX             => 100,
    OPACITY_MIN             => 0,
    LARGE_DISTANCE          => 1e9,
    ROUND_HALF              => 0.5,
    LAST_INDEX_OFFSET       => -1,
};

has pictures_dir => (
    is      => 'ro',
    default => sub { $ENV{HOME} . '/Pictures' },
);

has extensions => (
    is      => 'ro',
    default => sub { [qw(jpg jpeg png webp bmp tiff tif)] },
);

has thumb_height => (
    is      => 'ro',
    default => sub { DEFAULT_THUMB_HEIGHT },
);

has thumb_width => (
    is      => 'ro',
    default => sub { DEFAULT_THUMB_WIDTH },
);

has padding => (
    is      => 'ro',
    default => sub { DEFAULT_PADDING },
);

has fade_steps => (
    is      => 'ro',
    default => sub { DEFAULT_FADE_STEPS },
);

has fade_interval_ms => (
    is      => 'ro',
    default => sub { DEFAULT_FADE_INTERVAL },
);

has cache_dir => (
    is      => 'ro',
    default => sub {
        "$ENV{HOME}/.local/share/perl-wallpaper-picker/thumbnails";
    },
);

has scale => (
    is      => 'rw',
    default => sub { 1 },
);

has images => (
    is      => 'rw',
    default => sub { [] },
);

has selected_index => (
    is      => 'rw',
    default => sub { 0 },
);

has window => (
    is => 'rw',
);

has drawing_area => (
    is => 'rw',
);

has thumbnails => (
    is      => 'rw',
    default => sub { {} },
);

has scroll_offset => (
    is      => 'rw',
    default => sub { 0.0 },
);

has _settle_timer => (
    is      => 'rw',
    default => sub { 0 },
);

has _settling => (
    is      => 'rw',
    default => sub { 0 },
);

has _wheel_vel => (
    is      => 'rw',
    default => sub { 0.0 },
);

has _coasting => (
    is      => 'rw',
    default => sub { 0 },
);

sub BUILD {
    my ($self) = @_;
    $self->_load_images;
    $self->_build_window;
    return;
}

sub run {
    my ($self) = @_;
    $self->window->show_all;
    while (Gtk3::events_pending()) { Gtk3::main_iteration() }
    $self->_prewarm_thumbnails;
    Gtk3->main;
    return;
}

sub _load_images {
    my ($self) = @_;
    my $dir  = $self->pictures_dir;
    my @exts = @{ $self->extensions };
    my @files;
    for my $ext (@exts) {
        push @files, bsd_glob("$dir/*.$ext");
        push @files, bsd_glob("$dir/*.\U$ext");
    }
    my %seen;
    @files = grep { !$seen{$_}++ } sort @files;
    die "No images found in $dir\n" unless @files;
    $self->images(\@files);
    return;
}

sub _build_window {
    my ($self) = @_;

    my $screen   = Gtk3::Gdk::Screen::get_default();
    my $s_width  = $screen->get_width;
    my $s_height = $screen->get_height;
    my $strip_h  = $self->thumb_height + STRIP_LABEL_HEIGHT;

    my $win = Gtk3::Window->new('toplevel');
    $win->set_title('Wallpaper Picker');
    $win->set_decorated(FALSE);
    $win->set_keep_above(TRUE);
    $win->set_skip_taskbar_hint(TRUE);
    $win->set_skip_pager_hint(TRUE);
    $win->set_app_paintable(TRUE);
    $win->set_default_size($s_width, $strip_h);
    $win->move(0, int(($s_height - $strip_h) / 2));

    my $visual = $screen->get_rgba_visual;
    if ($visual) {
        $win->set_visual($visual);
    }

    my $da = Gtk3::DrawingArea->new;
    $da->set_size_request($s_width, $strip_h);
    $da->set_app_paintable(TRUE);
    $da->set_can_focus(TRUE);
    $da->add_events([
        'scroll-mask',
        'smooth-scroll-mask',
        'button-press-mask',
        'key-press-mask',
    ]);

    $da->signal_connect('draw'               => sub { $self->_on_draw(@_) });
    $da->signal_connect('scroll-event'       => sub { $self->_on_scroll(@_) });
    $da->signal_connect('button-press-event' => sub { $self->_on_click(@_) });

    $win->signal_connect('key-press-event' => sub { $self->_on_key(@_) });
    $win->signal_connect('destroy'         => sub { Gtk3->main_quit });

    $win->signal_connect('realize' => sub {
        my $gdk_win = $win->get_window;
        if ($gdk_win) {
            $self->scale($gdk_win->get_scale_factor // 1);
        }
        return;
    });

    $win->add($da);
    $self->window($win);
    $self->drawing_area($da);
    $da->grab_focus;
    return;
}

sub _on_draw {
    my ($self, $da, $cr) = @_;

    my $alloc   = $da->get_allocation;
    my $width   = $alloc->{width};
    my $height  = $alloc->{height};
    my $pad     = $self->padding;
    my $tw      = $self->thumb_width;
    my $th      = $self->thumb_height;
    my @images  = @{ $self->images };
    my $sel     = $self->selected_index;
    my $offset  = $self->scroll_offset;

    $cr->set_source_rgba(BG_R, BG_G, BG_B, BG_A);
    $cr->paint;

    my $thumb_y  = ($height - $th) / 2;
    my $cache    = $self->thumbnails;
    my $loaded   = grep { defined $cache->{$_} } @images;
    my $total    = @images;
    my $all_done = ($loaded == $total);

    if (!$all_done) {
        my $bar_y = $height - PROGRESS_BAR_H - PROGRESS_BAR_MARGIN;
        my $bar_w = int($width * $loaded / $total);
        $cr->set_source_rgba(PROG_R, PROG_G, PROG_B, PROG_A);
        $cr->rectangle(0, $bar_y, $bar_w, PROGRESS_BAR_H);
        $cr->fill;
    }

    for my $i (0 .. $#images) {
        my $x = $pad + $i * ($tw + $pad) - $offset;

        next if $x + $tw < 0 || $x > $width;

        my $pb = $self->_get_thumbnail($images[$i]);

        if ($i == $sel) {
            $cr->set_source_rgba(SEL_FILL_R, SEL_FILL_G, SEL_FILL_B, SEL_FILL_A);
            $cr->rectangle(
                $x - SELECTION_INSET, $thumb_y - SELECTION_INSET,
                $tw + SELECTION_OUTSET, $th + SELECTION_OUTSET,
            );
            $cr->fill;
            $cr->set_source_rgba(SEL_LINE_R, SEL_LINE_G, SEL_LINE_B, SEL_LINE_A);
            $cr->set_line_width(SEL_LINE_WIDTH);
            $cr->rectangle(
                $x - SELECTION_INSET, $thumb_y - SELECTION_INSET,
                $tw + SELECTION_OUTSET, $th + SELECTION_OUTSET,
            );
            $cr->stroke;
        }

        if ($pb) {
            my $sc = $self->scale || 1;
            $cr->save;
            $cr->scale(1.0 / $sc, 1.0 / $sc);
            Gtk3::Gdk::cairo_set_source_pixbuf($cr, $pb,
                $x * $sc, $thumb_y * $sc);
            $cr->paint;
            $cr->restore;
        }
        else {
            $cr->set_source_rgba(
                THUMB_UNLOADED_R, THUMB_UNLOADED_G,
                THUMB_UNLOADED_B, THUMB_UNLOADED_A,
            );
            $cr->rectangle($x, $thumb_y, $tw, $th);
            $cr->fill;
        }
    }

    return FALSE;
}

sub _cache_path {
    my ($self, $path) = @_;
    my $sc  = $self->scale || 1;
    my $key = sha1_hex("$path:${\$self->thumb_width}:${\$self->thumb_height}:$sc");
    return $self->cache_dir . '/' . $key . '.jpg';
}

sub _prewarm_thumbnails {
    my ($self) = @_;
    my @images  = @{ $self->images };
    my $da      = $self->drawing_area;

    make_path($self->cache_dir) unless -d $self->cache_dir;

    for my $i (0 .. $#images) {
        my $path       = $images[$i];
        my $cache_file = $self->_cache_path($path);

        if (! -e $cache_file) {
            eval { $self->_generate_and_cache($path, $cache_file); 1 }
                or warn "Failed to generate thumbnail for $path: $@\n";
        }

        my $ok = eval { $self->thumbnails->{$path} //=
            Gtk3::Gdk::Pixbuf->new_from_file($cache_file); 1 };
        if (!$ok) {
            warn "Failed to load thumbnail for $path: $@\n";
        }

        $da->queue_draw;
        while (Gtk3::events_pending()) { Gtk3::main_iteration() }
    }
    return;
}

sub _generate_and_cache {
    my ($self, $path, $cache_file) = @_;
    my $sc       = $self->scale || 1;
    my $target_w = $self->thumb_width  * $sc;
    my $target_h = $self->thumb_height * $sc;

    my $orig     = Gtk3::Gdk::Pixbuf->new_from_file($path);
    my $orig_w   = $orig->get_width;
    my $orig_h   = $orig->get_height;
    my $fill     = ($target_w / $orig_w) > ($target_h / $orig_h)
                 ? ($target_w / $orig_w) : ($target_h / $orig_h);
    my $scaled_w = int($orig_w * $fill + ROUND_HALF);
    my $scaled_h = int($orig_h * $fill + ROUND_HALF);
    my $scaled   = $orig->scale_simple($scaled_w, $scaled_h, 'bilinear');
    my $crop_x   = int(($scaled_w - $target_w) / 2);
    my $crop_y   = int(($scaled_h - $target_h) / 2);
    $crop_x = 0 if $crop_x < 0;
    $crop_y = 0 if $crop_y < 0;
    my $cropped  = $scaled->new_subpixbuf($crop_x, $crop_y, $target_w, $target_h);
    $cropped->savev($cache_file, 'jpeg', ['quality'], [JPEG_QUALITY]);
    return;
}

sub _get_thumbnail {
    my ($self, $path) = @_;
    my $cache = $self->thumbnails;

    if (!exists $cache->{$path}) {
        my $cache_file = $self->_cache_path($path);

        if (-e $cache_file) {
            my $ok = eval { $cache->{$path} =
                Gtk3::Gdk::Pixbuf->new_from_file($cache_file); 1 };
            if (!$ok) {
                warn "Could not load cached thumbnail $cache_file: $@\n";
                $cache->{$path} = undef;
            }
        }
        else {
            my $ok = eval {
                $self->_generate_and_cache($path, $cache_file);
                $cache->{$path} = Gtk3::Gdk::Pixbuf->new_from_file($cache_file);
                1;
            };
            if (!$ok) {
                warn "Could not generate thumbnail for $path: $@\n";
                $cache->{$path} = undef;
            }
        }
        $self->thumbnails($cache);
    }

    return $cache->{$path};
}

sub _on_scroll {
    my ($self, $da, $event) = @_;
    my $direction = $event->direction;
    my $tw        = $self->thumb_width;
    my $pad       = $self->padding;
    my $step      = int(($tw + $pad) / SCROLL_STEP_DIVISOR);

    if ($direction eq 'smooth') {
        my (undef, $dx, $dy) = $event->get_scroll_deltas;
        $dx //= 0;
        $dy //= 0;
        return TRUE if $dx == 0 && $dy == 0;
        my $delta = abs($dx) > abs($dy) ? $dx : $dy;

        if ($delta == int($delta)) {
            my $impulse = $step * ($delta > 0 ? 1 : -1);
            $self->_add_wheel_impulse($impulse);
        }
        else {
            $self->_wheel_vel(0);
            $self->_scroll_by($delta * ($tw + $pad));
            $self->_schedule_settle;
        }
    }
    elsif ($direction eq 'down' || $direction eq 'right') {
        $self->_add_wheel_impulse($step);
    }
    elsif ($direction eq 'up' || $direction eq 'left') {
        $self->_add_wheel_impulse(-$step);
    }

    return TRUE;
}

sub _add_wheel_impulse {
    my ($self, $impulse) = @_;

    my $vel = $self->_wheel_vel;
    if ($vel != 0 && ($vel > 0) != ($impulse > 0)) {
        $vel = 0;
    }
    $self->_wheel_vel($vel + $impulse);

    $self->_scroll_by($impulse);

    return if $self->_coasting;
    $self->_coasting(1);

    Glib::Timeout->add(COAST_TIMER_MS, sub {
        my $v = $self->_wheel_vel;
        $v   *= COAST_DECAY;
        $self->_wheel_vel($v);

        if (abs($v) < COAST_MIN_VEL) {
            $self->_wheel_vel(0);
            $self->_coasting(0);
            $self->_schedule_settle;
            return FALSE;
        }

        $self->_scroll_by($v);
        return TRUE;
    });
    return;
}

sub _schedule_settle {
    my ($self) = @_;
    if ($self->_settle_timer) {
        Glib::Source->remove($self->_settle_timer);
        $self->_settle_timer(0);
    }
    my $id = Glib::Timeout->add(SETTLE_DELAY_MS, sub {
        $self->_settle_timer(0);
        $self->_start_settle;
        return FALSE;
    });
    $self->_settle_timer($id);
    return;
}

sub _scroll_by {
    my ($self, $px) = @_;
    my $da     = $self->drawing_area;
    my $alloc  = $da->get_allocation;
    my $width  = $alloc->{width};
    my $tw     = $self->thumb_width;
    my $pad    = $self->padding;
    my $n      = scalar @{ $self->images };
    my $max    = $n * ($tw + $pad) - $width;
    $max       = 0 if $max < 0;

    $self->_settling(0);

    my $offset = $self->scroll_offset + $px;

    if ($offset <= 0) {
        $offset = 0;
        $self->_wheel_vel(0);
    }
    elsif ($offset >= $max) {
        $offset = $max;
        $self->_wheel_vel(0);
    }

    $self->scroll_offset($offset);
    $self->_update_selected_from_offset;
    $da->queue_draw;
    return;
}

sub _update_selected_from_offset {
    my ($self) = @_;
    my $da     = $self->drawing_area;
    my $alloc  = $da->get_allocation;
    my $width  = $alloc->{width};
    my $pad    = $self->padding;
    my $tw     = $self->thumb_width;
    my $offset = $self->scroll_offset;
    my $n      = scalar @{ $self->images };
    my $max    = $n * ($tw + $pad) - $width;
    $max       = 0 if $max < 0;

    if ($offset <= 0) {
        $self->selected_index(0);
        return;
    }
    if ($offset >= $max) {
        $self->selected_index($n - 1);
        return;
    }

    my $viewport_centre = $offset + $width / 2;
    my $best_i    = 0;
    my $best_dist = LARGE_DISTANCE;
    for my $i (0 .. $n - 1) {
        my $tile_centre = $pad + $i * ($tw + $pad) + $tw / 2;
        my $dist        = abs($tile_centre - $viewport_centre);
        if ($dist < $best_dist) {
            $best_dist = $dist;
            $best_i    = $i;
        }
    }
    $self->selected_index($best_i);
    return;
}

sub _start_settle {
    my ($self) = @_;
    my $pad    = $self->padding;
    my $tw     = $self->thumb_width;
    my $sel    = $self->selected_index;
    my $alloc  = $self->drawing_area->get_allocation;
    my $width  = $alloc->{width};
    my $n      = scalar @{ $self->images };
    my $max    = $n * ($tw + $pad) - $width;
    $max       = 0 if $max < 0;

    my $target = $pad + $sel * ($tw + $pad) + $tw / 2 - $width / 2;
    $target    = 0    if $target < 0;
    $target    = $max if $target > $max;

    $self->_settling(1);

    Glib::Timeout->add(SETTLE_TIMER_MS, sub {

        return FALSE unless $self->_settling;

        my $current = $self->scroll_offset;
        my $diff    = $target - $current;
        if (abs($diff) < SETTLE_THRESHOLD) {
            $self->scroll_offset($target);
            $self->_settling(0);
            $self->drawing_area->queue_draw;
            return FALSE;
        }
        $self->scroll_offset($current + $diff * SETTLE_EASE);
        $self->drawing_area->queue_draw;
        return TRUE;
    });
    return;
}

sub _snap_to_index {
    my ($self, $i) = @_;
    my $n = scalar @{ $self->images };
    $i    = 0      if $i < 0;
    $i    = $n - 1 if $i >= $n;
    $self->_wheel_vel(0);

    if ($self->_settle_timer) {
        Glib::Source->remove($self->_settle_timer);
        $self->_settle_timer(0);
    }
    $self->selected_index($i);
    $self->_start_settle;
    return;
}

sub _on_click {
    my ($self, $da, $event) = @_;
    my $x      = $event->x;
    my $pad    = $self->padding;
    my $tw     = $self->thumb_width;
    my @images = @{ $self->images };
    my $offset = $self->scroll_offset;

    for my $i (0 .. $#images) {
        my $tile_x = $pad + $i * ($tw + $pad) - $offset;
        if ($x >= $tile_x && $x <= $tile_x + $tw) {
            if ($i == $self->selected_index) {
                $self->_apply_wallpaper($images[$i]);
            }
            else {
                $self->_snap_to_index($i);
            }
            last;
        }
    }
    return TRUE;
}

sub _on_key {
    my ($self, $win, $event) = @_;
    my $key    = $event->keyval;
    my @images = @{ $self->images };
    my $sel    = $self->selected_index;

    my %dispatch = (
        Gtk3::Gdk::KEY_Right,    sub { $self->_key_move(1)  },
        Gtk3::Gdk::KEY_Left,     sub { $self->_key_move(LAST_INDEX_OFFSET) },
        Gtk3::Gdk::KEY_Down,     sub { $self->_key_move(1)  },
        Gtk3::Gdk::KEY_Up,       sub { $self->_key_move(LAST_INDEX_OFFSET) },
        Gtk3::Gdk::KEY_Return,   sub { $self->_apply_wallpaper($images[$sel]) },
        Gtk3::Gdk::KEY_KP_Enter, sub { $self->_apply_wallpaper($images[$sel]) },
        Gtk3::Gdk::KEY_Escape,   sub { Gtk3->main_quit },
    );

    if (my $handler = $dispatch{$key}) {
        $handler->();
        return TRUE;
    }

    return FALSE;
}

sub _key_move {
    my ($self, $delta) = @_;
    my $n   = scalar @{ $self->images };
    my $i   = $self->selected_index + $delta;
    $i      = 0      if $i < 0;
    $i      = $n - 1 if $i >= $n;
    $self->_wheel_vel(0);
    $self->_settling(0);
    if ($self->_settle_timer) {
        Glib::Source->remove($self->_settle_timer);
        $self->_settle_timer(0);
    }
    $self->selected_index($i);
    $self->_centre_on_selected;
    $self->drawing_area->queue_draw;
    return;
}

sub _centre_on_selected {
    my ($self) = @_;
    my $pad    = $self->padding;
    my $tw     = $self->thumb_width;
    my $sel    = $self->selected_index;
    my $alloc  = $self->drawing_area->get_allocation;
    my $width  = $alloc->{width};

    my $tile_centre = $pad + $sel * ($tw + $pad) + $tw / 2;
    my $desired     = $tile_centre - $width / 2;

    my $max = scalar(@{ $self->images }) * ($tw + $pad) - $width;
    $desired = 0    if $desired < 0;
    $desired = $max if $desired > $max && $max > 0;

    $self->scroll_offset($desired);
    return;
}

sub _apply_wallpaper {
    my ($self, $path) = @_;

    my $steps    = $self->fade_steps;
    my $interval = $self->fade_interval_ms;
    my $uri      = "file://$path";

    system qw(gsettings set org.cinnamon.desktop.background picture-opacity), OPACITY_MIN;
    system qw(gsettings set org.cinnamon.desktop.background picture-uri), $uri;

    my $step = 0;
    Glib::Timeout->add($interval, sub {
        $step++;
        my $opacity = int(OPACITY_MAX * $step / $steps);
        $opacity = OPACITY_MAX if $opacity > OPACITY_MAX;
        system qw(gsettings set org.cinnamon.desktop.background picture-opacity),
               $opacity;
        return $step < $steps ? TRUE : FALSE;
    });
    return;
}

package main;    ## no critic (Modules::ProhibitMultiplePackages)

my $picker = WallpaperPicker->new(
    # pictures_dir     => "$ENV{HOME}/Wallpapers",
    # thumb_height     => 300,
    # thumb_width      => 480,
    # fade_steps       => 20,
    # fade_interval_ms => 30,
);

$picker->run;
